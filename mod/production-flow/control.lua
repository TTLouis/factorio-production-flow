-- Production Flow — control stage entry point (event wiring only)

local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")
local UI = require("scripts.ui")
local RenderTest = require("scripts.render_test")
local Diag = require("scripts.diag")
local Canvas = require("scripts.canvas")
Sampler.logger = Diag.log

local STATS_EVERY = 60
local UI_REFRESH_EVERY = 300

local function setup(rescan)
  storage.test = storage.test or {}
  storage.ui = storage.ui or {}
  Graph.build()
  Sampler.init()
  if rescan then Sampler.rescan() end
  for _, p in pairs(game.players) do UI.ensure_button(p) end
  Diag.log(string.format("setup: mod %s, base %s, space-age %s, graph %d nodes / %d recipes",
    script.active_mods["production-flow"], script.active_mods["base"], tostring(script.active_mods["space-age"]),
    storage.graph.n_nodes, storage.graph.n_recipes))
end

script.on_init(function() setup(true) end)
script.on_configuration_changed(function()
  setup(true)
  for _, player in pairs(game.connected_players) do
    if UI.is_open(player) then UI.open(player) end
  end
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
  if e.setting == "ssk-window-seconds" then Sampler.init() end
  if e.setting == "ssk-debug-tabs" and e.player_index then
    local p = game.get_player(e.player_index)
    if p and UI.is_open(p) then UI.open(p) end
  end
end)

---------------------------------------------------------------------------
-- entity registry
---------------------------------------------------------------------------
local build_filter = { {filter="type",type="container"}, {filter="type",type="logistic-container"} }
for _, t in ipairs(Sampler.TYPES) do build_filter[#build_filter + 1] = { filter = "type", type = t } end

for _, name in ipairs({ "on_built_entity", "on_robot_built_entity", "script_raised_built",
                        "script_raised_revive", "on_space_platform_built_entity" }) do
  local id = defines.events[name]
  if id then
    script.on_event(id, function(e) Sampler.add(e.entity) end, build_filter)
  end
end
script.on_event(defines.events.on_entity_cloned, function(e) Sampler.add(e.destination) end, build_filter)
-- removals are handled lazily by the sampler (invalid entities are dropped on visit)

---------------------------------------------------------------------------
-- ticking
---------------------------------------------------------------------------
script.on_event(defines.events.on_tick, function(e)
  Sampler.on_tick(e.tick)
  if #storage.probes > 0 then Sampler.probe_tick(e.tick) end
end)

script.on_nth_tick(STATS_EVERY, function(e) Sampler.on_stats(e.tick) end)
script.on_nth_tick(UI_REFRESH_EVERY, function() UI.auto_refresh() end)
script.on_nth_tick(3600, function(e) Diag.auto(e.tick) end)
script.on_nth_tick(600, function(e) Sampler.on_stock(e.tick) end)

---------------------------------------------------------------------------
-- GUI events
---------------------------------------------------------------------------
script.on_event(defines.events.on_gui_click, function(e)
  if not (e.element and e.element.valid) then return end
  if UI.on_click(e) then return end
  RenderTest.on_click(e)
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(e) UI.on_checked(e) end)
script.on_event(defines.events.on_gui_elem_changed, function(e) UI.on_elem_changed(e) end)
script.on_event(defines.events.on_gui_text_changed, function(e) UI.on_text_changed(e) end)
script.on_event(defines.events.on_string_translated, function(e) UI.on_string_translated(e) end)
script.on_event(defines.events.on_gui_selected_tab_changed, function(e) UI.on_tab_changed(e) end)
script.on_event(defines.events.on_gui_selection_state_changed, function(e) UI.on_selection(e) end)
script.on_event(defines.events.on_gui_hover, function(e)
  if UI.on_hover(e, true) then return end
  RenderTest.on_hover(e, true)
end)
script.on_event(defines.events.on_gui_leave, function(e)
  if UI.on_hover(e, false) then return end
  RenderTest.on_hover(e, false)
end)

script.on_event(defines.events.on_gui_closed, function(e)
  if UI.on_closed(e) then return end
  RenderTest.on_closed(e)
end)

local function display_changed(e)
  local p = game.get_player(e.player_index)
  UI.on_display_changed(p)
  RenderTest.on_display_changed(p)
end
script.on_event(defines.events.on_player_display_resolution_changed, display_changed)
script.on_event(defines.events.on_player_display_scale_changed, display_changed)

---------------------------------------------------------------------------
-- commands
---------------------------------------------------------------------------
commands.add_command("sankey", "Toggle the Production Flow window.", function(cmd)
  local p = game.get_player(cmd.player_index)
  if p then UI.toggle(p) end
end)

commands.add_command("sankey-test", "Open the M0 render test. Optional: margin | screen", function(cmd)
  local p = game.get_player(cmd.player_index)
  if p then RenderTest.open(p, cmd.parameter) end
end)

commands.add_command("sankey-probe", "Hover a crafting machine: checks what products_finished counts over 10 s.", function(cmd)
  local p = game.get_player(cmd.player_index)
  if p then Sampler.probe_start(p) end
end)

commands.add_command("sankey-export", "Write diagnostics to script-output/production-flow/.", function(cmd)
  local p = game.get_player(cmd.player_index)
  if p then Diag.export(p, "manual") end
end)
