-- Material selector using vanilla filter-group controls, ordered subgroup rows
-- and native item slots. Its searchable contents include only items and fluids.
local P = {}
local NAME = "ssk_material_picker"

-- Blueprint parameters and signal/miscellaneous categories are not production
-- materials. Apply the same rule to browsing, search and translation requests.
local EXCLUDED_GROUPS = { signals = true, other = true }
local function selectable(proto)
  local group = proto.group or (proto.subgroup and proto.subgroup.group)
  return not proto.hidden and not proto.parameter
    and not EXCLUDED_GROUPS[group and group.name or "other"]
end

local function label(key)
  local kind, name = key:match("^(%a+)/(.+)$")
  local proto = prototypes[kind] and prototypes[kind][name]
  return { "", "[" .. kind .. "=" .. name .. "] ",
    proto and proto.localised_name or name:gsub("%-", " ") }
end

function P.button(row, key, target)
  local b = row.add { type = "sprite-button", style = "slot_button", sprite = key or "utility/search",
    tags = { ssk_picker = "open", target = target, current = key or "" },
    tooltip = key and { "", label(key), "\nChoose an item or fluid" } or "Choose an item or fluid" }
  b.style.width, b.style.height = 40, 40
  return b
end

local function state(player)
  storage.material_picker = storage.material_picker or {}
  local s = storage.material_picker[player.index]
  if not s or s.locale ~= player.locale then
    s = { locale = player.locale, names = {}, pending = {} }
    storage.material_picker[player.index] = s
  end
  return s
end

-- Use the game's filter-group buttons and deep slot grid, populated exclusively
-- from item/fluid prototypes. The signal choose-elem dialog cannot filter types.
local function populate(player)
  local f = player.gui.screen[NAME]
  if not f then return end
  local s, entries, groups, total = state(player), {}, {}, 0
  local query = f.ssk_query.text:lower()
  local chosen_group = query == "" and f.tags.group or ""
  for _, kind in ipairs({ "item", "fluid" }) do
    for name, proto in pairs(prototypes[kind]) do
      if selectable(proto) then
        local key = kind .. "/" .. name
        local group = kind == "fluid" and { name = "fluids", order = "zzzz", localised_name = { "item-group-name.fluids" } }
          or proto.group or (proto.subgroup and proto.subgroup.group)
          or { name = "other", order = "z", localised_name = "Other" }
        total = total + 1
        local subgroup = proto.subgroup or { name = kind, order = "" }
        groups[group.name] = group
        local display = s.names[key] or name:gsub("%-", " ")
        if query == "" or display:lower():find(query, 1, true)
          or name:lower():gsub("%-", " "):find(query, 1, true) then
          entries[#entries + 1] = { key = key, name = name, kind = kind, group = group.name,
            subgroup = group.name .. "/" .. subgroup.name,
            sort = (group.order or "") .. "\t" .. group.name .. "\t"
              .. (subgroup.order or "") .. "\t" .. subgroup.name .. "\t" .. (proto.order or "") .. "\t" .. name .. "\t" .. kind }
        end
      end
    end
  end
  table.sort(entries, function(a, b) return a.sort < b.sort end)
  local group_list = {}
  for _, group in pairs(groups) do group_list[#group_list + 1] = group end
  table.sort(group_list, function(a, b)
    if (a.order or "") ~= (b.order or "") then return (a.order or "") < (b.order or "") end
    return a.name < b.name
  end)
  if query == "" then
    if not chosen_group or chosen_group == "" or not groups[chosen_group] then
      chosen_group = group_list[1] and group_list[1].name or ""
      local tags = f.tags; tags.group = chosen_group; f.tags = tags
    end
    local visible = {}
    for _, entry in ipairs(entries) do if entry.group == chosen_group then visible[#visible + 1] = entry end end
    entries = visible
  end
  local tabs = f.ssk_material_inner.ssk_group_scroll.ssk_groups
  tabs.clear()
  for _, group in ipairs(group_list) do
    tabs.add { type = "sprite-button", style = "filter_group_button_tab_slightly_larger", sprite = "item-group/" .. group.name,
      toggled = chosen_group == group.name, tooltip = group.localised_name or group.name,
      tags = { ssk_picker = "group", group = group.name } }
  end
  local grid = f.ssk_material_inner.ssk_slot_frame.ssk_slot_scroll.ssk_results
  grid.clear()
  local keys, last, occupied = {}, nil, 0
  local columns = grid.column_count
  for _, entry in ipairs(entries) do
    if last and entry.subgroup ~= last then
      while occupied % columns ~= 0 do
        local gap = grid.add { type = "empty-widget" }
        gap.style.width, gap.style.height = 40, 40
        occupied = occupied + 1
      end
    end
    local b = grid.add { type = "sprite-button", style = "slot_button", sprite = entry.key,
      toggled = entry.key == f.tags.current, tooltip = label(entry.key),
      elem_tooltip = { type = entry.kind, name = entry.name },
      tags = { ssk_picker = "pick", key = entry.key } }
    keys[#keys + 1] = entry.key
    occupied, last = occupied + 1, entry.subgroup
  end
  grid.tags = { keys = keys, total = total }
  f.ssk_count.caption = #entries == 0 and "No matching materials" or (#entries .. " materials")
end

function P.on_group(e)
  local player = game.get_player(e.player_index)
  local f = player.gui.screen[NAME]
  if not f then return end
  local tags = f.tags
  tags.group = e.element.tags.group
  f.tags = tags
  f.ssk_query.text = ""
  populate(player)
end

function P.close(player)
  local f = player.gui.screen[NAME]
  if f then f.destroy() end
  local main = player.gui.screen.ssk_main
  if main then player.opened = main end
end

function P.open(player, target, current)
  P.close(player)
  local res, scale = player.display_resolution, player.display_scale
  local width = math.min(480, math.floor(res.width / scale) - 60)
  local height = math.min(640, math.floor(res.height / scale) - 100)
  local group = ""
  if current then
    local kind, name = current:match("^(%a+)/(.+)$")
    local proto = prototypes[kind] and prototypes[kind][name]
    group = kind == "fluid" and "fluids" or proto and proto.group and proto.group.name or ""
  end
  local f = player.gui.screen.add { type = "frame", name = NAME, direction = "vertical", tags = { target = target, group = group, current = current or "" } }
  f.style.width, f.style.height = width, height
  local title = f.add { type = "flow", direction = "horizontal" }
  title.style.horizontally_stretchable = true
  title.add { type = "label", caption = "Select item / fluid", style = "frame_title" }
  local drag = title.add { type = "empty-widget", style = "draggable_space_header" }
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = f
  title.add { type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
    tags = { ssk_picker = "close" }, tooltip = "Close material picker" }
  local query = f.add { type = "textfield", name = "ssk_query", text = "",
    tags = { ssk_picker = "query" }, tooltip = "Search item and fluid names" }
  query.style.width = width - 24
  local inner = f.add { type = "frame", name = "ssk_material_inner", style = "inside_shallow_frame", direction = "vertical" }
  inner.style.horizontally_stretchable, inner.style.vertically_stretchable = true, true
  local groups = inner.add { type = "scroll-pane", name = "ssk_group_scroll", style = "naked_scroll_pane",
    horizontal_scroll_policy = "auto", vertical_scroll_policy = "never" }
  groups.style.horizontally_stretchable = true
  groups.style.height = 88
  local tabs = groups.add { type = "flow", name = "ssk_groups", direction = "horizontal" }
  tabs.style.horizontal_spacing = 0
  local slots = inner.add { type = "frame", name = "ssk_slot_frame", style = "slot_button_deep_frame", direction = "vertical" }
  slots.style.padding = 0
  slots.style.horizontally_stretchable, slots.style.vertically_stretchable = true, true
  local scroll = slots.add { type = "scroll-pane", name = "ssk_slot_scroll", style = "naked_scroll_pane",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
  scroll.style.horizontally_stretchable, scroll.style.vertically_stretchable = true, true
  local grid = scroll.add { type = "table", name = "ssk_results", style = "filter_slot_table",
    column_count = math.max(1, math.floor((width - 52) / 40)) }
  grid.style.horizontal_spacing, grid.style.vertical_spacing = 0, 0
  local count = f.add { type = "label", name = "ssk_count", style = "grey_label" }
  count.style.font = "default-small"
  f.auto_center = true
  -- Keep the main frame as player.opened. Switching to the dialog raises a
  -- synchronous close event for the main frame, which would destroy both.
  if f.bring_to_front then f.bring_to_front() end
  if query.focus then query.focus() end
  local s = state(player)
  s.pending = {}
  local strings, keys = {}, {}
  for _, kind in ipairs({ "item", "fluid" }) do
    for name, proto in pairs(prototypes[kind]) do
      local key = kind .. "/" .. name
      if selectable(proto) and not s.names[key] then
        keys[#keys + 1] = key
        strings[#strings + 1] = proto.localised_name or name:gsub("%-", " ")
      end
    end
  end
  if #strings > 0 and player.request_translations then
    for i, id in ipairs(player.request_translations(strings)) do s.pending[id] = keys[i] end
  end
  populate(player)
end

function P.on_text_changed(e)
  if not (e.element.tags and e.element.tags.ssk_picker == "query") then return false end
  populate(game.get_player(e.player_index))
  return true
end

function P.on_translated(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  local s = state(player)
  local key = s.pending[e.id]
  if not key then return end
  s.pending[e.id] = nil
  if e.translated then s.names[key] = e.result end
  if not next(s.pending) then populate(player) end
end

function P.selection(e)
  local tags = e.element.tags
  if not (tags and tags.ssk_picker == "pick") then return false end
  local player = game.get_player(e.player_index)
  local f = player.gui.screen[NAME]
  local key = tags.key
  if not f or not key then return true end
  local target = f.tags.target
  P.close(player)
  return true, key, target
end

function P.on_closed(e)
  if not (e.element and e.element.valid and e.element.name == NAME) then return false end
  P.close(game.get_player(e.player_index))
  return true
end

return P
