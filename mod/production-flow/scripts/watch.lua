local Loc = require("scripts.locale")
-- Personal Balance thresholds. Evaluation uses the current Balance data only.
local Balance = require("scripts.balance")
local Groups = require("scripts.groups")
local Sampler = require("scripts.sampler")
local Surfaces = require("scripts.surfaces")

local Watch = { NAME = "ssk_watch" }
local OBSERVATION_TICKS = 300
local MAX_GAP_TICKS = 2 * OBSERVATION_TICKS

local function material(key)
  local kind, name = (key or ""):match("^(%a+)/(.+)$")
  local proto = (kind == "item" or kind == "fluid") and prototypes[kind][name]
  return kind, name, proto
end

function Watch.available(player_index, us, key)
  local favourites = us.bal_favs
  if not (favourites and key) then return false end
  local _, _, proto = material(key)
  if not proto then return false end
  if favourites.items and favourites.items[key] then return true end
  local groups = favourites.groups
  return groups ~= nil and next(groups) ~= nil and groups[Groups.of(player_index, key)] == true
end

local function on_surface(us, surface)
  return us.bal_watches and us.bal_watches[surface]
end

function Watch.get(us, surface, key)
  local watches = on_surface(us, surface)
  return watches and watches[key]
end

local function set(us, surface, key, watch)
  local watches = on_surface(us, surface)
  if watch then
    us.bal_watches = us.bal_watches or {}
    watches = watches or {}
    us.bal_watches[surface] = watches
    watches[key] = watch
  elseif watches then
    watches[key] = nil
    if not next(watches) then us.bal_watches[surface] = nil end
  end
end

local function reset_pending(watch)
  watch.made_since, watch.empty_since = nil, nil
end

function Watch.pause_unstarred(player_index, us)
  for _, watches in pairs(us.bal_watches or {}) do
    for key, watch in pairs(watches) do
      if not Watch.available(player_index, us, key) then reset_pending(watch) end
    end
  end
end

function Watch.reset_pending(us, key)
  for _, watches in pairs(us.bal_watches or {}) do
    if key then
      if watches[key] then reset_pending(watches[key]) end
    else
      for _, watch in pairs(watches) do reset_pending(watch) end
    end
  end
end

-- Unknown data interrupts a pending breach and hides its warning. A latched
-- condition needs a measured recovery to re-arm.
local function observe(watch, since, latched, breach, tick)
  if breach == nil then
    watch[since] = nil
    return false
  end
  if not breach then
    watch[since], watch[latched] = nil, nil
    return false
  end
  if watch[latched] then return true end
  local start = watch[since]
  if not start then
    watch[since] = tick
  elseif tick - start >= OBSERVATION_TICKS then
    watch[since], watch[latched] = nil, true
    return true
  end
  return false
end

local function empty_minutes(stock, net)
  if not stock or stock.count == 0 then return 0 end
  local seconds = Balance.time_to_empty(stock, net)
  return seconds and seconds / 60 or math.huge
end

function Watch.evaluate(player, us, seconds, stock, stock_known, nodes)
  local watches = on_surface(us, us.sidx)
  if not watches then return end

  local period = us.period or Sampler.DEFAULT_PERIOD
  local window = period > 0 and period or settings.global["ssk-window-seconds"].value
  local ready = type(seconds) == "number" and seconds >= window and nodes ~= nil
  local tick = game.tick
  local warnings = {}
  for key, watch in pairs(watches) do
    if Watch.available(player.index, us, key) then
      local last = watch.last_observed
      if watch.window ~= window or not last or tick < last or tick - last > MAX_GAP_TICKS then
        reset_pending(watch)
      end
      watch.window, watch.last_observed = window, tick
      local made_breach, empty_breach, produced, minutes
      if ready then
        local measured = nodes[key]
        produced = measured and measured.prod or 0
        if watch.made then made_breach = produced < watch.made end
        if watch.empty and stock_known and stock and key:sub(1, 5) == "item/" then
          minutes = empty_minutes(stock[key], produced - (measured and measured.cons or 0))
          empty_breach = minutes < watch.empty
        end
      end
      local low_made = observe(watch, "made_since", "made_latched", made_breach, tick)
      local low_empty = observe(watch, "empty_since", "empty_latched", empty_breach, tick)
      if low_made or low_empty then
        local warning = Loc("watch-watch-warning")
        if low_made then
          local unit = key:sub(1, 6) == "fluid/" and Loc("unit-fluid-rate") or Loc("history-items-s")
          warning = Loc.join(warning, Loc("watch-made-below", string.format("%.4g", produced), unit, string.format("%.4g", watch.made), unit))
        end
        if low_empty then
          warning = Loc.join(warning, Loc("watch-chest-stock-empty-in-min-below-min", string.format("%.4g", minutes), string.format("%.4g", watch.empty)))
        end
        warnings[key] = warning
      end
    else
      reset_pending(watch)
    end
  end
  return warnings
end

function Watch.close(player)
  local f = player.gui.screen[Watch.NAME]
  if not f then return false end
  f.destroy()
  return true
end

local function number_field(fields, name, caption, value, enabled)
  fields.add { type = "label", caption = caption }
  local field = fields.add { type = "textfield", name = name, text = value and tostring(value) or "",
    numeric = true, allow_decimal = true }
  field.enabled = enabled
  field.style.width = 110
  return field
end

function Watch.open(player, us, surface, key)
  if not Watch.available(player.index, us, key) then return end
  Watch.close(player)
  local kind, name, proto = material(key)
  local watch = Watch.get(us, surface, key) or {}
  local f = player.gui.screen.add { type = "frame", name = Watch.NAME, direction = "vertical",
    tags = { surface = surface, key = key } }
  local title = f.add { type = "flow", direction = "horizontal" }
  title.style.vertical_align = "center"
  title.add { type = "label", caption = Loc("watch-material-watch"), style = "frame_title", ignored_by_interaction = true }
  local drag = title.add { type = "empty-widget", style = "draggable_space_header" }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = f
  title.add { type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
    tags = { ssk_ui = "watch_close" }, tooltip = Loc("watch-close-material-watch") }

  local body = f.add { type = "frame", name = "ssk_watch_body", direction = "vertical",
    style = "inside_shallow_frame_with_padding" }
  local caption = Loc("material-on-surface", Loc.join("[img=" .. key .. "] ", proto.localised_name or name), Surfaces.rich(game.surfaces[surface]))
  local material_label = body.add { type = "label", caption = caption, style = "caption_label" }
  material_label.style.maximal_width = 430
  material_label.style.single_line = false
  local fields = body.add { type = "table", name = "ssk_watch_fields", column_count = 2 }
  local made = number_field(fields, "ssk_watch_made", kind == "fluid" and Loc("watch-minimum-made-fluid-s") or Loc("watch-minimum-made-items-s"),
    watch.made, true)
  local empty = number_field(fields, "ssk_watch_empty", Loc("watch-minimum-time-to-empty-minutes"), watch.empty, kind == "item")
  empty.tooltip = kind == "item" and Loc("watch-uses-completed-chest-stock-scans-and-the")
    or Loc("watch-chest-stock-is-unavailable-for-fluids")
  local hint = body.add { type = "label", style = "grey_label", caption = Loc("watch-leave-a-field-blank-to-turn-off") }
  hint.style.single_line = false
  local error_label = body.add { type = "label", name = "ssk_watch_error", style = "red_label" }
  error_label.visible = false

  local actions = f.add { type = "flow", direction = "horizontal", style = "dialog_buttons_horizontal_flow" }
  local remove = actions.add { type = "button", caption = Loc("watch-remove"), style = "red_back_button", tags = { ssk_ui = "watch_remove" } }
  remove.enabled = watch.made ~= nil or watch.empty ~= nil
  local space = actions.add { type = "empty-widget", style = "draggable_space" }
  space.style.horizontally_stretchable = true
  actions.add { type = "button", caption = Loc("watch-apply"), style = "confirm_button", tags = { ssk_ui = "watch_apply" } }

  f.auto_center = true
  -- The main frame stays opened so Esc can close this dialog first.
  if f.bring_to_front then f.bring_to_front() end
  if made.focus then made.focus() end
  return f
end

local function threshold(field)
  if not field.enabled or field.text:match("^%s*$") then return nil end
  local value = tonumber(field.text)
  if not value or value <= 0 or value == math.huge then return false end
  return value
end

function Watch.apply(player, us, surface, key, remove)
  local f = player.gui.screen[Watch.NAME]
  if not f then return false end
  if f.tags.surface ~= surface or f.tags.key ~= key or not Watch.available(player.index, us, key) then
    Watch.close(player)
    return false
  end
  if remove then
    set(us, surface, key, nil)
  else
    local body = f.ssk_watch_body
    local fields = body.ssk_watch_fields
    local made, empty = threshold(fields.ssk_watch_made), threshold(fields.ssk_watch_empty)
    if made == false or empty == false then
      body.ssk_watch_error.caption = Loc("watch-enter-a-number-greater-than-zero-or")
      body.ssk_watch_error.visible = true
      return false
    end
    local watch = Watch.get(us, surface, key)
    if not watch or watch.made ~= made or watch.empty ~= empty then
      set(us, surface, key, (made or empty) and { made = made, empty = empty } or nil)
    end
  end
  Watch.close(player)
  return true
end

return Watch
