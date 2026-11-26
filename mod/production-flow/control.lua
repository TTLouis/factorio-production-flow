local Loc = require("scripts.locale")
-- Production Flow — control stage entry point (event wiring only)

local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")
local UI = require("scripts.ui")
local CellOutlines = require("scripts.cell_outlines")
local Canvas = require("scripts.canvas")
local Transfers = require("scripts.transfers")
local SERockets = require("scripts.se_rockets")
local SECannons = require("scripts.se_cannons")
local Cells = require("scripts.cells")
local CellRail = require("scripts.cell_rail")
local CellCapacity = require("scripts.cell_capacity")

local STATS_EVERY = 60
local UI_REFRESH_STRIDE, UI_REFRESH_SLOTS = 6, 50 -- One pass per player every 300 ticks.

local function setup(rescan)
  storage.test = storage.test or {}
  storage.ui = storage.ui or {}
  Graph.build()
  CellCapacity.index()
  Sampler.init()
  if SERockets.available() then SERockets.init(game.tick) end
  if SECannons.available() then SECannons.init(game.tick) end
  if rescan then Sampler.rescan() end
  -- Rebuild cell slot and sampler attribution indexes after an upgrade or mod change.
  if storage.production_cells then Cells.reindex() end
  for _, p in pairs(game.players) do UI.ensure_button(p) end
end

if SECannons.available() then
  script.on_event(defines.events.on_script_trigger_effect, function(e) SECannons.on_effect(e) end)
end

-- SE declares public custom events in the data stage. Registration occurs on
-- every control load (including save reload), with no private SE state access.
if SERockets.available() then
  script.on_event(defines.events.se_on_cargo_rocket_launched, SERockets.on_launch)
  if type(defines.events.se_on_cargo_rocket_padless)=="number" then
    script.on_event(defines.events.se_on_cargo_rocket_padless, SERockets.on_padless)
  end
end

script.on_init(function() setup(true) end)
script.on_configuration_changed(function()
  setup(true)
  UI.sanitize_saved_states()
  for _, player in pairs(game.connected_players) do
    if UI.is_open(player) then UI.open(player) end
  end
end)

script.on_event(defines.events.on_player_controller_changed, function(e)
  CellOutlines.on_controller_changed(e)
end)

script.on_event(defines.events.on_player_removed, function(e)
  UI.on_player_removed(e.player_index)
  Cells.on_player_removed(e.player_index)
end)

script.on_event(defines.events.on_player_created, function(e)
  UI.ensure_button(game.get_player(e.player_index))
end)

script.on_event(defines.events.on_player_joined_game, function(e)
  local player = game.get_player(e.player_index)
  if UI.is_open(player) then UI.open(player) end
end)

script.on_event(defines.events.on_force_created, function(e) Canvas.on_force_created(e.force) end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if e.setting == "ssk-live-sankey-overview" and e.player_index then
    local player = game.get_player(e.player_index)
    if player then UI.on_sankey_viewport_setting_changed(player) end
  end
  if e.setting == "ssk-window-seconds" then Sampler.init() end
  if e.setting == "ssk-stock-scan-minutes" then Sampler.on_stock_interval_changed() end
  if e.setting == "ssk-allow-small-window" then
    local player = e.player_index and game.get_player(e.player_index)
    if player then UI.on_display_changed(player) end
  end
  if e.setting == "ssk-return-direction-markers" then
    local player = e.player_index and game.get_player(e.player_index)
    if player and UI.is_open(player) then UI.refresh(player) end
  end
end)

---------------------------------------------------------------------------
-- entity registry
---------------------------------------------------------------------------
local build_filter = { {filter="type",type="container"}, {filter="type",type="logistic-container"},
  {filter="type",type="temporary-container"}, {filter="type",type="cargo-landing-pad"}, {filter="type",type="space-platform-hub"} }
for _, t in ipairs(Sampler.TYPES) do build_filter[#build_filter + 1] = { filter = "type", type = t } end

for _, name in ipairs({ "on_built_entity", "on_robot_built_entity", "script_raised_built",
                        "script_raised_revive", "on_space_platform_built_entity" }) do
  local id = defines.events[name]
  if id then
    script.on_event(id, function(e) Sampler.add(e.entity); Cells.on_built(e.entity) end, build_filter)
  end
end
script.on_event(defines.events.on_entity_cloned, function(e)
  Sampler.add(e.destination)
  Cells.on_cloned(e.source, e.destination)
end, build_filter)
-- removals are handled lazily by the sampler (invalid entities are dropped on visit)

local track_cargo = Transfers.available()
if track_cargo then
  if defines.events.on_space_platform_changed_state then
    script.on_event(defines.events.on_space_platform_changed_state, Transfers.on_platform_changed_state)
  end
  -- Platform cargo leaves the hub when ascent starts. Capture that manifest
  -- before a storage scan can establish a newer, already-unloaded baseline.
  if defines.events.on_cargo_pod_started_ascending then
    script.on_event(defines.events.on_cargo_pod_started_ascending, Transfers.on_departed)
  end
  if defines.events.on_rocket_launch_ordered then
    script.on_event(defines.events.on_rocket_launch_ordered, Transfers.on_rocket_launch_ordered)
  end
  script.on_event(defines.events.on_cargo_pod_finished_ascending, Transfers.on_departed)
  script.on_event(defines.events.on_cargo_pod_finished_descending, Transfers.on_landed)
  script.on_event(defines.events.on_cargo_pod_delivered_cargo, function(e)
    -- Surface drops create their container internally, without a built event.
    if e.spawned_container then Sampler.add(e.spawned_container) end
    Transfers.on_delivered(e)
  end)
end

script.on_event(defines.events.on_pre_surface_deleted, function(e)
  Sampler.on_surface_deleted(e.surface_index)
  Cells.on_surface_deleted(e.surface_index)
  if track_cargo then Transfers.on_surface_deleted(e) end
end)

---------------------------------------------------------------------------
-- ticking
---------------------------------------------------------------------------
-- Mod set and SE version are fixed for a loaded session. Both SE hooks return
-- immediately when nothing is in flight. Production Flow loads after SE, so
-- these run after SE's own on_tick handlers in the same tick.
local se_rockets_active = SERockets.available()
local se_cannons_active = SECannons.available()
script.on_event(defines.events.on_train_changed_state, CellRail.on_state)
script.on_event(defines.events.on_train_created, CellRail.on_train_created)
script.on_event(defines.events.on_tick, function(e)
  UI.release_chart_zoom(e.tick)
  Sampler.on_tick(e.tick)
  CellRail.on_tick(e.tick)
  local cells = storage.production_cells
  if cells and cells.clones then Cells.resolve_clones() end
  if se_rockets_active then SERockets.on_tick(e.tick) end
  if se_cannons_active then SECannons.on_tick(e.tick) end
end)

script.on_nth_tick(STATS_EVERY, function(e) Sampler.on_stats(e.tick) end)
script.on_nth_tick(UI_REFRESH_STRIDE, function(e) UI.auto_refresh(e.tick / UI_REFRESH_STRIDE, UI_REFRESH_SLOTS) end)
script.on_nth_tick(600, function(e)
  Sampler.on_stock(e.tick)
  if track_cargo then Transfers.on_housekeeping(e.tick) end
  if SERockets.available() then SERockets.prune(e.tick) end
  if SECannons.available() then SECannons.prune(e.tick) end
end)

---------------------------------------------------------------------------
-- GUI events
---------------------------------------------------------------------------
script.on_event(defines.events.on_gui_click, function(e)
  if not (e.element and e.element.valid) then return end
  if UI.on_click(e) then return end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(e) UI.on_checked(e) end)
script.on_event(defines.events.on_gui_switch_state_changed, function(e) UI.on_switch(e) end)
script.on_event(defines.events.on_gui_elem_changed, function(e) UI.on_elem_changed(e) end)
script.on_event(defines.events.on_gui_text_changed, function(e) UI.on_text_changed(e) end)
script.on_event(defines.events.on_string_translated, function(e) Cells.on_string_translated(e); UI.on_string_translated(e) end)
script.on_event(defines.events.on_gui_selected_tab_changed, function(e) UI.on_tab_changed(e) end)
script.on_event(defines.events.on_gui_selection_state_changed, function(e) UI.on_selection(e) end)
script.on_event(defines.events.on_gui_value_changed, function(e) UI.on_value_changed(e) end)
script.on_event(defines.events.on_gui_location_changed, UI.on_chart_location_changed)
script.on_event(defines.events.on_gui_hover, function(e)
  if UI.on_hover(e, true) then return end
end)
script.on_event(defines.events.on_gui_leave, function(e)
  if UI.on_hover(e, false) then return end
end)

script.on_event(defines.events.on_gui_closed, function(e)
  if UI.on_closed(e) then return end
end)

local function display_changed(e)
  local p = game.get_player(e.player_index)
  UI.on_display_changed(p)
end
script.on_event(defines.events.on_player_display_resolution_changed, display_changed)
script.on_event(defines.events.on_player_display_scale_changed, display_changed)
script.on_event(defines.events.on_player_selected_area, Cells.on_selected)
script.on_event(require("shared.cell_selection").click, Cells.on_click_anywhere)
for _, wheel in ipairs({{"up",0,-48},{"down",0,48},{"left",-48,0},{"right",48,0}}) do
  script.on_event("ssk-sankey-scroll-"..wheel[1], function(e) UI.on_chart_wheel(e,wheel[2],wheel[3]) end)
end
script.on_event("ssk-sankey-page-left", function(e) UI.on_chart_page(e,-1) end)
script.on_event("ssk-sankey-page-right", function(e) UI.on_chart_page(e,1) end)
script.on_event(defines.events.on_player_cursor_stack_changed, function(e)
  Cells.on_cursor_changed(game.get_player(e.player_index))
end)
script.on_event(defines.events.on_player_changed_surface, function(e)
  local player = game.get_player(e.player_index)
  Cells.cancel(player)
  UI.on_surface_changed(player)
end)
script.on_event(defines.events.on_player_changed_force, function(e)
  local player = game.get_player(e.player_index)
  Cells.cancel(player)
  UI.on_force_changed(player)
end)

---------------------------------------------------------------------------
-- commands
---------------------------------------------------------------------------
commands.add_command("sankey", Loc("control-toggle-the-production-flow-window"), function(cmd)
  local p = game.get_player(cmd.player_index)
  if p then UI.toggle(p) end
end)
