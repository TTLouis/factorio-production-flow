local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")
local Surfaces = require("scripts.surfaces")

local M = {}
local STATUS, PREVIEW, MAIN = "ssk_machine_status", "ssk_machine_preview", "ssk_main"
local CAMERA, ZOOM = "ssk_machine_camera", "ssk_machine_zoom"
local DEFAULT_ZOOM = 0.85
local ISSUES = {
  { id = "input", heading = "Missing input", narrow = "Input" },
  { id = "output", heading = "Blocked output", narrow = "Output" },
  { id = "power", heading = "Power", narrow = "Power" },
}

local function frame(player, name, width, title)
  local f = player.gui.screen.add { type = "frame", name = name, direction = "vertical" }
  f.style.width = width
  local header = f.add { type = "flow", direction = "horizontal" }
  header.drag_target = f
  header.style.vertical_align = "center"
  header.add { type = "label", caption = title, style = "frame_title", ignored_by_interaction = true }
  local drag = header.add { type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true }
  drag.style.horizontally_stretchable, drag.style.height = true, 24
  f.auto_center = true
  if f.bring_to_front then f.bring_to_front() end
  return f, header
end

local function header_button(header, sprite, tooltip, action)
  header.add { type = "sprite-button", style = "frame_action_button", sprite = "utility/" .. sprite,
    tooltip = tooltip, tags = { ssk_machine_status = action } }
end

local function dimensions(player, max_width, max_height)
  local resolution, scale = player.display_resolution, player.display_scale
  return math.min(max_width, math.floor(resolution.width / scale) - 32),
         math.min(max_height, math.floor(resolution.height / scale) - 48)
end

local function caption(kind, name)
  local proto = prototypes[kind] and prototypes[kind][name]
  local plain = name:gsub("%-", " ")
  local label = proto and proto.localised_name and { "?", proto.localised_name, plain } or plain
  return { "", Graph.rt(kind .. "/" .. name), " ", label }
end

local function age(tick)
  local seconds = math.max(0, math.floor((game.tick - tick) / 60))
  if seconds == 0 then return "<1 s" end
  if seconds < 60 then return seconds .. " s" end
  return string.format("%d m %02d s", math.floor(seconds / 60), seconds % 60)
end

local function columns(width)
  local cells = width >= 500 and { 98, 110, 62, 88 } or { 58, 60, 58, 58 }
  -- Leave room for the two frame paddings, cell spacing and scroll rail.
  table.insert(cells, 1, width - cells[1] - cells[2] - cells[3] - cells[4] - 72)
  return cells
end

local function grid(parent)
  local t = parent.add { type = "table", column_count = 5 }
  t.style.horizontal_spacing, t.style.vertical_spacing = 4, 4
  return t
end

local function cell(parent, width)
  local f = parent.add { type = "flow", direction = "horizontal" }
  f.style.width, f.style.vertical_align = width, "center"
  return f
end

local function add_headings(parent, widths, compact)
  local t = grid(parent)
  cell(t, widths[1]).add { type = "label", style = "heading_2_label", caption = "Recipe" }
  for i, issue in ipairs(ISSUES) do
    cell(t, widths[i + 1]).add { type = "label", style = "heading_2_label",
      caption = compact and issue.narrow or issue.heading, tooltip = issue.heading }
  end
  cell(t, widths[5]).add { type = "label", style = "heading_2_label",
    caption = compact and "Age" or "Sample age", tooltip = "Time since the latest observation of this recipe." }
end

local function add_recipes(parent, title, names, rows, widths)
  parent.add { type = "label", style = "caption_label", caption = title }
  local shown, seen = {}, {}
  for _, name in ipairs(names) do
    if rows[name] and not seen[name] then
      seen[name] = true
      shown[#shown + 1] = name
    end
  end
  if #shown == 0 then
    parent.add { type = "label", style = "grey_label", caption = "No machines observed." }
    return
  end
  table.sort(shown)
  local t = grid(parent)
  for _, name in ipairs(shown) do
    local row = rows[name]
    local recipe = caption("recipe", name)
    local label = cell(t, widths[1]).add { type = "label", caption = recipe, tooltip = recipe }
    label.style.maximal_width = widths[1]
    for i, issue in ipairs(ISSUES) do
      local f = cell(t, widths[i + 1])
      local observation = row.issues[issue.id]
      local count = tostring(observation and observation.count or 0)
      local count_label = f.add { type = "label", name = "ssk_machine_count", caption = count,
        style = observation and "semibold_label" or "grey_label", tooltip = observation and count or nil }
      if observation then
        f.style.horizontal_spacing = 4
        count_label.style.maximal_width = widths[i + 1] - 28
        local inspect = f.add { type = "sprite-button", style = "tool_button", sprite = "utility/search",
          tooltip = issue.heading .. ". Preview one matching machine.",
          tags = { ssk_machine_status = "preview", recipe = name, issue = issue.id } }
        inspect.style.width, inspect.style.height = 24, 24
      end
    end
    cell(t, widths[5]).add { type = "label", caption = age(row.sample_tick),
      tooltip = "Time since the latest observation of this recipe. The counts combine samples taken at different times.",
      tags = { ssk_machine_age = name, sample_tick = row.sample_tick } }
  end
end

function M.close(player)
  local screen = player.gui.screen
  if screen[PREVIEW] then screen[PREVIEW].destroy() end
  if screen[STATUS] then screen[STATUS].destroy() end
end

function M.open(player, surface, material)
  M.close(player)
  local width, height = dimensions(player, 610, 530)
  local f, header = frame(player, STATUS, width, "Machine status")
  f.tags = { surface = surface, material = material or "", force = player.force_index }
  header_button(header, "refresh", "Refresh machine status counts", "refresh")
  header_button(header, "close", "Close machine status", "close")
  local panel = f.add { type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical",
    name = "ssk_machine_panel" }
  panel.style.horizontally_stretchable = true
  local note = panel.add { type = "label", name = "ssk_machine_notice", style = "red_label", visible = false }
  note.style.single_line, note.style.maximal_width = false, width - 40
  local graph = Graph.get()
  local node = graph.nodes[material]
  if not node then
    panel.add { type = "label", caption = "Select an item or fluid to see its machine status." }
    return f
  end
  local scope = panel.add { type = "label", style = "caption_label",
    caption = { "", caption(node.type, node.name), " on ", Surfaces.rich(game.surfaces[surface]) } }
  scope.style.single_line, scope.style.maximal_width = false, width - 40
  local rows, warming = Sampler.machine_status(surface, player.force_index)
  local hint = panel.add { type = "label", style = "grey_label", caption = warming
    and "First pass in progress. Refresh as more machines are sampled."
    or "Latest observations across machines. Refresh to update counts and age." }
  hint.style.single_line, hint.style.maximal_width = false, width - 40
  local widths = columns(width)
  local strip = panel.add { type = "frame", style = "subheader_frame", direction = "horizontal" }
  strip.style.horizontally_stretchable = true
  strip.style.left_padding = 0
  add_headings(strip, widths, width < 500)
  local scroller = panel.add { type = "scroll-pane", style = "naked_scroll_pane",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
  scroller.style.horizontally_stretchable = true
  scroller.style.maximal_height = math.max(56, height - 180)
  local list = scroller.add { type = "flow", direction = "vertical" }
  list.style.vertical_spacing = 8
  add_recipes(list, "Producers", node.producers, rows or {}, widths)
  add_recipes(list, "Consumers", node.consumers, rows or {}, widths)
  return f
end

local function close_preview(player)
  local screen = player.gui.screen
  if screen[PREVIEW] then screen[PREVIEW].destroy() end
  local status = screen[STATUS]
  if status then
    status.visible = true
    if status.bring_to_front then status.bring_to_front() end
  end
end

local function show_unavailable(player)
  close_preview(player)
  local f = player.gui.screen[STATUS]
  if not f then return end
  local notice = f.ssk_machine_panel.ssk_machine_notice
  notice.caption = "No matching machine is currently available. Refresh the counts and try again."
  notice.visible = true
end

local function open_preview(player, status, tags)
  local scope = status.tags
  if player.force_index ~= scope.force then
    M.open(player, scope.surface, scope.material)
    return
  end
  local entity = Sampler.find_status_machine(scope.surface, scope.force, tags.recipe, tags.issue)
  if not entity then show_unavailable(player); return end
  local width, height = dimensions(player, 560, 390)
  local f, header = frame(player, PREVIEW, width, "Machine preview")
  f.tags = { unit = entity.unit_number, surface = scope.surface, force = scope.force,
    recipe = tags.recipe, issue = tags.issue }
  header_button(header, "left_arrow", "Back to machine status", "back")
  local panel = f.add { type = "frame", style = "inside_deep_frame", direction = "vertical" }
  panel.style.horizontally_stretchable = true
  local toolbar = panel.add { type = "frame", style = "subheader_frame", direction = "horizontal" }
  toolbar.style.horizontally_stretchable, toolbar.style.vertical_align = true, "center"
  toolbar.add { type = "label", style = "subheader_caption_label", caption = "Zoom" }
  local slider = toolbar.add { type = "slider", name = ZOOM, minimum_value = 0.25, maximum_value = 2,
    value = DEFAULT_ZOOM, value_step = 0.05, tags = { ssk_machine_status = "zoom" } }
  slider.style.width = math.min(180, width - 135)
  toolbar.add { type = "empty-widget" }.style.horizontally_stretchable = true
  toolbar.add { type = "sprite-button", style = "tool_button", sprite = "utility/go_to_arrow",
    tooltip = "Jump to this machine in remote view", tags = { ssk_machine_status = "jump" } }
  local camera = panel.add { type = "camera", name = CAMERA, surface_index = scope.surface,
    position = entity.position, zoom = DEFAULT_ZOOM }
  camera.style.width, camera.style.height = width - 24, math.max(70, height - 100)
  status.visible = false
end

local function preview_entity(player, preview)
  local t = preview.tags
  if player.force_index == t.force then return Sampler.status_machine(t.unit, t.surface, t.force, t.recipe, t.issue) end
end

function M.on_click(player, element, close_all)
  local tags = element.tags
  local action = tags and tags.ssk_machine_status
  local status = player.gui.screen[STATUS]
  if not action or not status then return false end
  if action == "close" then
    M.close(player)
  elseif action == "refresh" then
    local scope = status.tags
    M.open(player, scope.surface, scope.material)
  elseif action == "preview" then
    if not player.gui.screen[PREVIEW] then open_preview(player, status, tags) end
  elseif action == "back" then
    close_preview(player)
  elseif action == "jump" then
    local preview = player.gui.screen[PREVIEW]
    local entity = preview and preview_entity(player, preview)
    if not entity then show_unavailable(player); return true end
    close_all(player)
    player.centered_on = entity
  else
    return false
  end
  return true
end

function M.on_value_changed(player, element)
  if not (element and element.valid and element.tags.ssk_machine_status == "zoom") then return false end
  local preview = player.gui.screen[PREVIEW]
  if not preview then return false end
  local camera = element.parent.parent[CAMERA]
  if camera then camera.zoom = element.slider_value end
  return true
end

function M.on_closed(player, element)
  local screen = player.gui.screen
  if not (screen[STATUS] and element and element.valid) then return false end
  if element.name ~= MAIN and element.name ~= STATUS and element.name ~= PREVIEW then return false end
  if screen[PREVIEW] then close_preview(player) else M.close(player) end
  if screen[MAIN] then player.opened = screen[MAIN] end
  return true
end

return M
