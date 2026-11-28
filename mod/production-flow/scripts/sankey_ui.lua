local Loc = require("scripts.locale")
-- M4–M7 Sankey tab: toolbar (presets, scope, tiers, zoom, live), selection toolbar
-- (▲/▼, hide, group/collapse), and the canvas drawn with stretched ribbon sprites.

local S = require("shared.sprites")
local palette = require("shared.palette")
local Balance = require("scripts.balance")
local BalanceUI = require("scripts.balance_ui")
local View = require("scripts.view")
local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")
local Gr = require("scripts.groups")
local Canvas = require("scripts.canvas")
local Geometry = require("scripts.ribbon_geometry")
local MaterialPicker = require("scripts.material_picker")
local Watch = require("scripts.watch")
local Tooltip = require("scripts.tooltip")
local RecipeDetails = require("scripts.recipe_details")
local RateCard = require("scripts.rate_card_ui")

local SK = {}
local ZOOM_STEP = 1.25
local SIDEBAR_MIN_W = 690
local INSPECTOR_W = 328

local function round(v) return math.floor(v + 0.5) end

-- Focus remembers the last few materials only; Last visits stays a short list.
local HISTORY_LIMIT = 6

local function trim_history(list)
  while list and #list > HISTORY_LIMIT do table.remove(list, 1) end
end

function SK.defaults(us)
  us.view = us.view or "detail"
  us.tier_mode = us.tier_mode or "depth"
  us.input_depth = math.max(1, math.min(View.MAX_INPUT_DEPTH, us.input_depth or 1))
  us.preset = us.preset or "all"
  if us.view ~= "focus" then
    us.layout = us.layout or "clean"
    us.heights = us.heights or "sqrt"
    us.lines = us.lines or "curves"
  end
  us.zoom = us.zoom or 1
  if us.live == nil then us.live = true end
  if us.show_labels == nil then us.show_labels = false end
  us.hidden = us.hidden or {}
  us.collapsed = us.collapsed or {}
  us.pos = us.pos or {}
  us.last_order = us.last_order or {}
  trim_history(us.focus_hist)
  trim_history(us.focus_forward)
end

-- Same rate formatting as the Balance table, so a value reads identically in both.
local function fmt(x)
  local a = math.abs(x)
  if a >= 1000000 then return Loc("balance-m", string.format("%.2f", x / 1000000)) end
  if a >= 10000 then return Loc("balance-k", string.format("%.1f", x / 1000)) end
  if a >= 100 then return string.format("%.0f", x) end
  if a >= 10 then return string.format("%.1f", x) end
  if a >= 1 then return string.format("%.2f", x) end
  if a > 0 and a < 0.001 then return "<0.001" end
  return string.format("%.3f", x)
end

local function rt(key)
  local t, n = string.match(key, "^(%a+)/(.+)$")
  if t == "group" then return "▣" end
  return Loc.join("[", t, "=", n, "]")
end

local function base_key(key) return (string.gsub(key, "#.*$", "")) end

local function material_key(n)
  local key = base_key(n.transport and n.transport.material or n.key)
  local kind = key:match("^(%a+)/")
  return (kind == "item" or kind == "fluid") and key or nil
end

local function transport_caption(transport)
  local kind,name=transport.material:match("^(%a+)/(.+)$")
  local prototype=prototypes[kind] and prototypes[kind][name]
  return Loc(transport.direction=="imports" and "transport-flow-import-material" or "transport-flow-export-material",
    prototype and prototype.localised_name or name)
end
local function transport_tags(transport,node,us)
  local tags={ssk_ui="transport_history",ssk_sk=node and "node" or "ribbon",key=node and node.key,fx=us and us.view=="focus"}
  for key,value in pairs(transport.history or {}) do tags[key]=value end
  return tags
end
local function method_name(method)
  if method=="cargo-pod" then return Loc("transport-history-cargo-pods") end
  return Loc(method=="cannon" and "se-ui-cannon" or "se-ui-rocket")
end
local function transport_tooltip(transport,clickable)
  local evidence=transport.evidence
  local parts={transport_caption(transport),"\n",
    Loc("transport-flow-sent",evidence.sent~=nil and string.format("%.0f",evidence.sent) or "—"),"\n",
    Loc("transport-flow-received",evidence.received~=nil and string.format("%.0f",evidence.received) or "—"),"\n",
    transport.rate~=nil and Loc("transport-flow-boundary-rate",fmt(transport.rate)) or Loc("transport-flow-unknown")}
  for i,route in ipairs(evidence.routes or {}) do
    if i>8 then parts[#parts+1]=Loc.join("\n",Loc("transport-flow-more-routes",#evidence.routes-8));break end
    parts[#parts+1]=Loc.join("\n",method_name(route.method)," · ",route.remote_name or Loc("se-ui-unknown-surface"))
  end
  if evidence.sent_partial or evidence.received_partial then parts[#parts+1]=Loc.join("\n",Loc("transport-flow-partial")) end
  if clickable then parts[#parts+1]=Loc.join("\n",Loc("transport-flow-open-history")) end
  return Tooltip.lines(parts)
end
local function external_supply(n)
  if not n.external_imports then return nil end
  local parts={Loc("transport-flow-external-supply")}
  for _,entry in ipairs(n.external_imports) do
    parts[#parts+1]="\n"
    parts[#parts+1]=transport_tooltip({direction="imports",material=entry.material,evidence=entry.evidence,rate=entry.evidence.received_rate})
  end
  return Tooltip.lines(parts)
end

local function display_name(n)
  if n.transport then return transport_caption(n.transport) end
  if n.caption then return n.caption end
  if n.kind == "group" then return Loc(n.flow_kind == "fluid" and "group-fluid-count" or "group-item-count", n.ginfo.localised_name or n.ginfo.name, #n.members) end
  local kind, name = base_key(n.key):match("^(%a+)/(.+)$")
  local proto = prototypes[kind] and prototypes[kind][name]
  return proto and proto.localised_name or (name or n.key):gsub("%-", " ")
end

local function units(n)
  return (n.kind == "fluid" or n.flow_kind == "fluid") and Loc("unit-fluid-rate")
    or n.kind == "recipe" and Loc("sankey-crafts-s") or Loc("history-items-s")
end

local function sprite_for(n)
  if n.transport then return n.transport.material end
  if n.sprite then return n.sprite end
  if n.kind == "group" then
    local t, name = string.match(n.members[1], "^(%a+)/(.+)$")
    return Loc.join(t, "/", name)
  end
  return base_key(n.key)
end

local function localised_name(n)
  if n.transport then return transport_caption(n.transport) end
  if n.caption then return n.caption end
  if n.kind == "group" then return n.ginfo.localised_name or n.ginfo.name end
  local kind, name = base_key(n.key):match("^(%a+)/(.+)$")
  local proto = prototypes[kind] and prototypes[kind][name]
  return proto and proto.localised_name or (name or n.key):gsub("%-", " ")
end

local function recipe_name(key)
  return localised_name({key=key})
end

local function observed_recipe_icons(player, us)
  local observations = Sampler.machine_status(us.sidx or player.surface.index, player.force_index) or {}
  local icons = {}
  return function(key)
    if not key then return end
    if icons[key] == nil then
      local row = observations[key:sub(8)]
      local machines = {}
      for name in pairs(row and row.entities or {}) do machines[#machines + 1] = name end
      table.sort(machines)
      for i, name in ipairs(machines) do machines[i] = rt("entity/" .. name) end
      icons[key] = #machines > 0 and Loc.join_list(machines, " ") or false
    end
    return icons[key] or nil
  end
end

local function ribbon_tooltip(link, recipe_icons)
  if link.transport then return transport_tooltip(link.transport,true) end
  local function name(node)
    return { "", rt(sprite_for(node)), " ", localised_name(node) }
  end
  local material = link.a.kind == "recipe" and link.b or link.a
  local parts = { name(link.a), " → ", name(link.b),
    Loc("sankey-total-flow", string.format("%.5g", link.rate), units(material)) }
  local details = link.details or {}
  if #details > 0 then parts[#parts + 1] = Loc("sankey-flow-by-recipe") end
  table.sort(details, function(a, b)
    if a.rate ~= b.rate then return a.rate > b.rate end
    if a.from ~= b.from then return a.from < b.from end
    if a.to ~= b.to then return a.to < b.to end
    return a.recipe < b.recipe
  end)
  for _, detail in ipairs(details) do
    local from = { key = detail.from, kind = detail.from:match("^(%a+)/") }
    local to = { key = detail.to, kind = detail.to:match("^(%a+)/") }
    local icons = recipe_icons and recipe_icons(detail.recipe)
    local row = { "", icons and Loc.join("\n", icons, " ") or "\n", name(from), " → ", name(to),
      Loc.join("  ", Loc("history-formatted", string.format("%.5g", detail.rate), units(from.kind == "recipe" and to or from))) }
    if detail.recipe ~= detail.from and detail.recipe ~= detail.to then
      row[#row + 1] = Loc.join(" ", Loc("flow-via-recipe", recipe_name(detail.recipe)))
    end
    parts[#parts + 1] = row
  end
  if link.note then parts[#parts + 1] = Loc.join("\n", link.note) end
  return Tooltip.lines(parts)
end

local function recipe_lines(node, rows, limit, recipe_icons)
  local lines = {}
  limit = limit or #rows
  for i = 1, math.min(#rows, limit) do
    local row = rows[i]
    local icons = recipe_icons and recipe_icons(row.recipe)
    local caption = recipe_name(row.recipe)
    if icons then caption = Loc.join(icons, " ", caption) end
    lines[#lines + 1] = Loc("sankey-recipe-rate", caption, fmt(row.rate), units(node))
  end
  if #rows > limit then
    local rate = 0
    for i = limit + 1, #rows do rate = rate + rows[i].rate end
    lines[#lines + 1] = Loc("sankey-more-recipe-rates", #rows - limit, fmt(rate), units(node))
  end
  return lines
end

local function recipe_summary(node, limit, recipe_icons, masked_only)
  local r, lines = node.recipe_rows, {}
  if not r then return lines end
  local function add(title, rows)
    if #rows == 0 then return end
    lines[#lines + 1] = title
    for _, line in ipairs(recipe_lines(node, rows, limit, recipe_icons)) do lines[#lines + 1] = line end
  end
  if not masked_only then
    add(Loc("sankey-made-by"), r.made)
    add(Loc("sankey-used-by"), r.used)
  end
  if #r.masked_made + #r.masked_used > 0 then
    lines[#lines + 1] = Loc("sankey-masked-recipes")
    add(Loc("sankey-made-by"), r.masked_made)
    add(Loc("sankey-used-by"), r.masked_used)
  end
  return lines
end

local function label_toggle(row, us)
  return row.add { type = "checkbox", name = "ssk_show_labels", caption = Loc("sankey-show-labels"),
    state = us.show_labels == true, tags = { ssk_sk = "show_labels" },
    tooltip = Loc("sankey-keep-all-names-and-rates-visible-otherwise") }
end
SK.label_toggle = label_toggle

local function live_toggle(row, us)
  return row.add { type = "checkbox", caption = Loc("sankey-auto-update-chart"), state = us.live, tags = { ssk_sk = "live" },
    tooltip = Loc("sankey-redraw-this-chart-every-5-seconds-sampling") }
end

---------------------------------------------------------------------------
-- placement (negative-margin absolute positioning, verified in M0)
---------------------------------------------------------------------------
-- Keep wrappers tight around their children: empty space in a tall flow catches
-- clicks meant for earlier rows. Cancel height and Y in separate equal lengths,
-- so fractional GUI scaling cannot accumulate rounding drift between overlays.
local function place_raw(e, x, y, w, h, reset)
  local s = e.style
  s.width, s.height = w, h
  s.left_margin, s.right_margin = x, 0
  s.top_margin, s.bottom_margin = y, -(y + h)
  if e.type == "flow" then
    s.bottom_margin = -h
    reset = reset or e.parent.add { type = "empty-widget", ignored_by_interaction = true,
      tags = { ssk_position_reset = true } }
    reset.style.width, reset.style.height = 0, 0
    reset.style.left_margin, reset.style.bottom_margin = 0, 0
    reset.style.top_margin = -y
    return reset
  end
end

-- Round the edges together in layout coordinates. The ribbon sprite path
-- also accounts for Factorio truncating each scaled widget size separately.
local function place(e, x, y, w, h, reset)
  local x2, y2 = round(x + w), round(y + h)
  x, y = round(x), round(y)
  w, h = math.max(1, x2 - x), math.max(1, y2 - y)
  local p = e.parent
  if p and p.tags and p.tags.ssk_wrap then
    reset = place_raw(p, x, y, w, h, reset)
    e.style.width, e.style.height = w, h
    e.style.top_margin = 0
  else
    reset = place_raw(e, x, y, w, h, reset)
  end
  return reset
end

local function add_sprite(parent, sprite, tooltip, direction)
  local f = parent.add { type = "flow", direction = direction or "horizontal", tags = { ssk_wrap = true } }
  f.style.padding = 0
  if direction == "vertical" then f.style.vertical_spacing = 0 else f.style.horizontal_spacing = 0 end
  local e = f.add { type = "sprite", sprite = sprite, tooltip = tooltip, resize_to_sprite = false }
  e.style.stretch_image_to_widget_size = true
  return e
end

---------------------------------------------------------------------------
-- toolbar
---------------------------------------------------------------------------
local ACTION_SPRITES = {
  f_back = "left_arrow", f_forward = "right_arrow", center_selection = "center",
  reflow = "refresh", chart_settings = "ssk-gear", reset_layout = "reset",
  unpin = "track_button", inputs_more = "add", overview_reset = "collapse",
  up = "indication_arrow", down = "down_arrow", hide = "filter_blacklist", expand = "expand", collapse = "collapse",
  new_group = "add", ungroup = "reset", deselect = "close", unhide_all = "grid_view",
}
local function button(parent, caption, action, tooltip, extra)
  local tags = { ssk_sk = action }
  if extra then for k, v in pairs(extra) do tags[k] = v end end
  local sprite = ACTION_SPRITES[action]
  if sprite then
    return parent.add { type = "sprite-button", style = action == "reset_layout" and "tool_button_red" or "tool_button",
      sprite = sprite:find("^ssk%-") and sprite or Loc.join("utility/", sprite), tooltip = tooltip or caption, tags = tags }
  end
  -- Vanilla has no zoom or fit utility sprite. Its square tool button keeps
  -- the game graphics, hover state, dimensions and click sound for these captions.
  assert(action == "zoom_in" or action == "zoom_out" or action == "zoom_fit" or action == "inputs_less", Loc("sankey-missing-toolbar-sprite", action))
  local b = parent.add { type = "button", style = "tool_button", caption = caption, tooltip = tooltip or caption, tags = tags }
  if action ~= "zoom_fit" then b.style.width = 28 end
  return b
end

local function small(parent, caption)
  return parent.add { type = "label", caption = caption }
end

-- secondary guidance text: small and grey in every toolbar
local function hint(parent, caption, width)
  local l = parent.add { type = "label", caption = caption }
  l.style.font = "default-small"
  l.style.font_color = { 0.65, 0.65, 0.65 }
  l.style.single_line = false
  l.style.maximal_width = width
  return l
end

-- Controls shared by the Balance chart, Focus and Full Sankey toolbars. Each one
-- has the same caption, order, width and tooltip wherever it appears.
-- Toolbar strip spacing, the same on every chart: 12 px at the sides, 8 px above,
-- below and between rows. The first row is slot height (the material slot);
-- later rows are tool-button height.
local STRIP_PAD_X, STRIP_PAD_Y, FIRST_ROW_H, ROW_H = 12, 8, 40, 28

local function option_row(bar, name)
  local row = bar.add { type = "flow", name = name, direction = "horizontal" }
  row.style.vertical_align = "center"
  row.style.horizontal_spacing = 8
  row.style.height = ROW_H
  return row
end

local function right_group(row, us, has_middle)
  row.style.width = math.max(240, (us.toolbar_width or us.canvas_w or 900) - 2 * STRIP_PAD_X)
  if not has_middle then
    local spacer = row.add { type = "empty-widget", tags = { ssk_toolbar_spacer = true } }
    spacer.style.horizontally_stretchable = true
    spacer.style.minimal_width = 16
    spacer.style.height = 1
  end
  local right = option_row(row, "ssk_toolbar_actions")
  right.tags = { ssk_toolbar_side = "right" }
  return right
end

local function dropdown(row, caption, items, index, action, tooltip)
  small(row, caption)
  local d = row.add { type = "drop-down", items = items, selected_index = index, tags = { ssk_sk = action }, tooltip = tooltip }
  d.style.width = 150
  return d
end

local function widths_picker(row, us)
  return dropdown(row, Loc("sankey-widths"), { Loc("sankey-proportional"), Loc("sankey-compressed") }, us.heights == "linear" and 1 or 2, "f_heights",
    Loc("sankey-proportional-linear-rate-widths-compressed-square-root"))
end

local function colors_picker(row, us)
  return dropdown(row, Loc("sankey-colors"), { Loc("sankey-destination"), Loc("sankey-source") }, us.color_mode == "source" and 2 or 1, "balance_colors",
    Loc("sankey-destination-ribbons-feeding-the-same-node-share"))
end

local function lines_picker(row, us)
  return dropdown(row, Loc("sankey-lines"), { Loc("sankey-curves"), Loc("sankey-right-angles") }, us.lines == "metro" and 2 or 1, "f_lines",
    Loc("sankey-right-angles-steep-ribbons-run-vertically-and"))
end

local function zoom_buttons(row, compact, zoom)
  button(row, "−", "zoom_out", Loc("sankey-zoom-out"))
  if zoom then
    local value = row.add{type="label", name="ssk_zoom", caption=Loc("sankey-chart-zoom", round(zoom * 100))}
    value.style.width = 46
    value.style.horizontal_align = "center"
    button(row, "+", "zoom_in", Loc("sankey-zoom-in"))
    button(row, Loc("sankey-fit"), "zoom_fit", Loc("sankey-fit-entire-chart"))
  else
    button(row, Loc("sankey-fit"), "zoom_fit", Loc("sankey-fit-the-chart-to-the-window-while"))
    button(row, "+", "zoom_in", Loc("sankey-zoom-in"))
  end
  if not compact then button(row, Loc("sankey-center"), "center_selection", Loc("sankey-center-the-selected-item-or-the-whole")) end
end

SK.zoom_buttons = zoom_buttons
function SK.zoom_caption(us)
  return Loc("sankey-chart-zoom", round((us.render_zoom or 1) * 100))
end

local function reflow_button(row)
  button(row, Loc("sankey-reflow"), "reflow", Loc("sankey-recalculate-node-order-and-spacing-auto-update"))
end

local function settings_button(row, us)
  local b = button(row, Loc("sankey-chart-settings"), "chart_settings",
    Loc("sankey-chart-settings-widths-colors-lines-layout-and"))
  b.name = "ssk_chart_settings"
  b.toggled = us.settings_open == true
  return b
end
SK.settings_button = settings_button

-- Chart settings float over the chart's top-right corner, so opening them never
-- moves or resizes the chart. Every row is a 28 px control, so the frame height
-- is known and the panel takes no layout height of its own.
local function settings_panel(c, us, L, W, viewH, allow_auto_update)
  if c.ssk_settings then c.ssk_settings.destroy() end
  if not us.settings_open then return end
  local cell_chart = us.is_cell_chart == true
  local full = us.view ~= "focus" and not cell_chart
  local panel = c.add { type = "frame", name = "ssk_settings", style = "frame", direction = "vertical" }
  -- The inner frame draws 8 px outside its bounds. Leave another 8 px visible
  -- below that graphic, matching the outer frame's side inset.
  panel.style.bottom_padding = 16
  local title = panel.add { type = "flow", direction = "horizontal" }
  title.style.vertical_align = "center"
  title.style.height = 24
  title.style.bottom_margin = 8
  title.add { type = "label", caption = Loc("sankey-chart-settings"), style = "frame_title", ignored_by_interaction = true }
  title.add { type = "empty-widget", ignored_by_interaction = true }.style.horizontally_stretchable = true
  title.add { type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
    tooltip = Loc("sankey-close-chart-settings-esc"), tags = { ssk_sk = "chart_settings" } }
  local inner = panel.add { type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" }
  inner.style.horizontally_stretchable = true
  local grid = inner.add { type = "table", column_count = 2 }
  grid.style.vertical_spacing = 8
  grid.style.horizontal_spacing = 12
  local rows = 0
  local function line(caption)
    rows = rows + 1
    local name = grid.add { type = "flow", direction = "horizontal" }
    name.style.vertical_align = "center"
    name.style.height = 28
    small(name, caption)
    local cell = grid.add { type = "flow", direction = "horizontal" }
    cell.style.vertical_align = "center"
    cell.style.horizontal_spacing = 8
    cell.style.height = 28
    return cell
  end
  local function picker(caption, items, index, action, tooltip)
    local d = line(caption).add { type = "drop-down", items = items, selected_index = index, tags = { ssk_sk = action }, tooltip = tooltip }
    d.style.width = 180
    return d
  end
  picker(Loc("sankey-widths"), { Loc("sankey-proportional"), Loc("sankey-compressed") }, us.heights == "linear" and 1 or 2, "f_heights",
    Loc("sankey-proportional-linear-rate-widths-compressed-square-root"))
  picker(Loc("sankey-colors"), { Loc("sankey-destination"), Loc("sankey-source") }, us.color_mode == "source" and 2 or 1, "balance_colors",
    Loc("sankey-destination-ribbons-feeding-the-same-node-share"))
  picker(Loc("sankey-lines"), { Loc("sankey-curves"), Loc("sankey-right-angles") }, us.lines == "metro" and 2 or 1, "f_lines",
    Loc("sankey-right-angles-steep-ribbons-run-vertically-and"))
  if us.neighborhood then
    local cell = line(Loc("sankey-inputs"))
    local fewer = button(cell, "−", "inputs_less", Loc("sankey-hide-the-furthest-upstream-step"))
    fewer.enabled = (us.input_depth or 1) > 1
    local more = button(cell, Loc("sankey-expand-inputs"), "inputs_more", Loc("sankey-reveal-another-upstream-production-step-up-to"))
    more.enabled = (us.input_depth or 1) < View.MAX_INPUT_DEPTH
    small(cell, Loc("input-step-count", us.input_depth or 1))
  elseif cell_chart then
    -- Cells Flow shares Widths, Colors, Lines, Auto-update and layout actions.
  elseif not full then
    picker(Loc("sankey-steps"), { "1", "2", "3" }, us.focus_steps or 2, "f_steps", Loc("sankey-item-steps-to-include-upstream-and-downstream"))
  else
    picker(Loc("sankey-layout"), { Loc("sankey-routed-columns"), Loc("sankey-swimlanes") }, (us.layout == "lanes") and 2 or 1, "layout",
      Loc("sankey-routed-columns-reserve-item-headers-and-long"))
    local tiers = picker(Loc("sankey-tiers-by"), { Loc("sankey-tech-era-depth"), Loc("sankey-production-depth") },
      (us.view == "overview" or us.tier_mode == "depth") and 2 or 1, "tier_mode",
      Loc("sankey-overview-uses-production-depth-because-groups-span"))
    tiers.enabled = us.view ~= "overview"
    local titems, lo_i, hi_i = {}, 1, 1
    us.tier_vals = {}
    for i, t in ipairs(L and L.all_tiers or {}) do
      titems[i] = View.tier_label(t)
      us.tier_vals[i] = t
      if us.tier_lo and t <= us.tier_lo + 1e-9 then lo_i = i end
      if not us.tier_hi or t <= us.tier_hi + 1e-9 then hi_i = i end
    end
    if #titems == 0 then titems = { Loc("sankey-t0") } end
    local range = line(Loc("sankey-range"))
    range.add { type = "drop-down", items = titems, selected_index = lo_i, tags = { ssk_sk = "tier_lo" } }.style.width = 86
    small(range, Loc("sankey-to"))
    range.add { type = "drop-down", items = titems, selected_index = math.max(lo_i, hi_i), tags = { ssk_sk = "tier_hi" } }.style.width = 86
    line("").add { type = "checkbox", caption = Loc("sankey-split-raw-inputs"), state = us.split_raw ~= false, tags = { ssk_sk = "split_raw" },
      tooltip = Loc("sankey-ores-oil-water-get-one-copy-per") }
  end
  if allow_auto_update ~= false then
    local live = live_toggle(line(""), us)
    if us.oversized then
      live.enabled, live.state = false, false
      live.tooltip = Loc("sankey-size-unlimited")
    end
  end
  local actions = line("")
  if not full then button(actions, Loc("sankey-center"), "center_selection", Loc("sankey-center-the-selected-material")) end
  reflow_button(actions)
  button(actions, Loc("sankey-unpin"), "unpin", full and Loc("sankey-clear-the-pinned-highlight-click-a-node") or Loc("sankey-clear-the-pinned-chain-highlight"))
  if full then button(actions, Loc("sankey-reset-layout"), "reset_layout", Loc("sankey-forget-manual-ordering-hidden-items-and-collapsed")) end
  -- Include the native 4 px gap between the title and content, so the inner
  -- frame and last controls stay inside the outer frame's bottom padding.
  local width, height = full and 360 or 330, 4 + 24 + 8 + 4 + 24 + rows * 28 + (rows - 1) * 8 + 16
  local top = -viewH + 8
  panel.style.width, panel.style.height = width, height
  panel.style.left_margin = math.max(0, W - width - 24)
  panel.style.top_margin, panel.style.bottom_margin = top, -(top + height)
end

local function material_caption(key)
  local kind, name = key:match("^(%a+)/(.+)$")
  local proto = prototypes[kind] and prototypes[kind][name]
  return { "", Loc.join("[", kind, "=", name, "] "), proto and proto.localised_name or name:gsub("%-", " ") }
end

-- History after the item picker on the same line: Back/Forward, the Last visits
-- list, the visited icons leading to the current material, and Clear.
local function history_controls(row, us)
  local divider = row.add { type = "line", direction = "vertical" }
  divider.style.height = ROW_H
  local back, forward = us.focus_hist or {}, us.focus_forward or {}
  local caption = material_caption
  local previous = button(row, "◀", "f_back", #back > 0 and Loc("sankey-back-to", caption(back[#back])) or Loc("sankey-no-previous-material"))
  previous.enabled = #back > 0
  local next_ = button(row, "▶", "f_forward", #forward > 0 and Loc("sankey-forward-to", caption(forward[#forward])) or Loc("sankey-no-next-material"))
  next_.enabled = #forward > 0
  local items, steps = { Loc("sankey-last-visits") }, {}
  for i = #(us.focus_hist or {}), 1, -1 do
    steps[#steps + 1] = -(#back - i + 1)
    items[#items + 1] = { "", "◀ ", caption(back[i]) }
  end
  for i = #forward, 1, -1 do
    steps[#steps + 1] = #forward - i + 1
    items[#items + 1] = { "", "▶ ", caption(forward[i]) }
  end
  local recent = row.add { type = "drop-down", items = items, selected_index = 1,
    tags = { ssk_sk = "f_history", steps = steps }, tooltip = Loc("sankey-jump-to-a-material-you-viewed-earlier") }
  recent.style.width = 160
  recent.enabled = #items > 1
  -- visited icons are tool-button sized so the line keeps the toolbar height
  local slots = math.max(0, math.min(HISTORY_LIMIT, math.floor(((us.toolbar_width or us.canvas_w or 900) - 900) / 56)))
  local first = math.max(1, #back - slots + 1)
  if first > 1 then small(row, "…") end
  for i = first, #back do
    local visit = row.add { type = "sprite-button", style = "slot_button", sprite = back[i],
      tooltip = Loc("sankey-return-to", caption(back[i])), tags = { ssk_sk = "f_trail", steps = -(#back - i + 1) } }
    visit.style.size = 28
    local arrow = row.add { type = "sprite", sprite = "utility/right_arrow", resize_to_sprite = false }
    arrow.style.width, arrow.style.height = 12, 12
    arrow.style.stretch_image_to_widget_size = true
  end
  if us.focus then
    local current = small(row, caption(us.focus))
    current.style.maximal_width = 140
    current.style.font = "default-bold"
    current.style.single_line = true
    current.tooltip = Loc("sankey-current-material", caption(us.focus))
  end
  local clear = row.add { type = "sprite-button", style = "tool_button_red", sprite = "utility/trash",
    tags = { ssk_sk = "f_clear_history" },
    tooltip = Loc("sankey-clear-selected-material-and-last-visits") }
  clear.enabled = us.focus ~= nil or #back + #forward > 0
end

-- Every toolbar row sits in one subheader strip across the top of the chart panel,
-- as vanilla panels put their controls.
local function toolbar_strip(bar)
  bar.clear()
  local strip = bar.add { type = "frame", name = "ssk_toolbar_strip", style = "subheader_frame",
    direction = "vertical", tags = { ssk_primary_controls = true } }
  strip.style.height = SK.toolbar_height()
  strip.style.horizontally_stretchable = true
  strip.style.left_padding, strip.style.right_padding = STRIP_PAD_X, STRIP_PAD_X
  strip.style.top_padding, strip.style.bottom_padding = STRIP_PAD_Y, STRIP_PAD_Y
  local rows = strip.add { type = "flow", name = "ssk_toolbar_rows", direction = "vertical" }
  local first = option_row(rows, "ssk_toolbar_main")
  first.style.height = FIRST_ROW_H
  return first
end

local function machine_action(parent, key)
  return parent.add { type = "sprite-button", name = "ssk_machine_action", style = "tool_button", sprite = "utility/map",
    tags = { ssk_ui = "machine_status", key = key }, tooltip = Loc("sankey-inspect-machines-that-make-or-use-this") }
end

local function focus_toolbar(bar, us, player)
  local main = toolbar_strip(bar)
  if us.neighborhood then
    local heading = MaterialPicker.add_heading(main, us.toolbar_width)
    MaterialPicker.update_heading(heading, us.focus)
  else
    small(main, Loc("material-picker-item-fluid"))
    MaterialPicker.button(main, us.focus, "focus")
    history_controls(main, us)
  end
  local actions = right_group(main, us)
  if us.neighborhood then
    actions.add { type = "sprite-button", name = "ssk_watch_action", style = "tool_button", sprite = "utility/warning",
      tags = { ssk_ui = "watch" }, tooltip = Loc("sankey-configure-this-material-s-watch") }
  end
  machine_action(actions).enabled = us.focus ~= nil
  actions.add{type = "sprite-button", name = "ssk_rate_card_action", style = "tool_button", sprite = "utility/clock",
    enabled = us.focus ~= nil, tags = {ssk_ui = "rate_card"}, tooltip = Loc("rate-card-open")}
  zoom_buttons(actions, true, us.zoom or 1)
  label_toggle(actions, us)
  settings_button(actions, us)
end

function SK.update_balance_actions(panel, us, key, player_index)
  local bar = panel.ssk_bar
  local strip = bar and bar.ssk_toolbar_strip
  local actions = strip and strip.ssk_toolbar_rows.ssk_toolbar_main.ssk_toolbar_actions
  if not actions then return end
  local watch, machines = actions.ssk_watch_action, actions.ssk_machine_action
  watch.enabled = Watch.available(player_index, us, key)
  watch.toggled = watch.enabled and Watch.get(us, us.sidx, key) ~= nil
  watch.tooltip = watch.enabled and Loc("sankey-configure-this-material-s-watch-on-the")
    or Loc("sankey-star-this-material-or-its-group-to")
  machines.enabled = key ~= nil
  if actions.ssk_rate_card_action then actions.ssk_rate_card_action.enabled = key ~= nil end
end

local function selection_links(row, key)
  local function pair(name)
    local flow = row.add{type="flow", name=name, direction="horizontal"}
    flow.style.horizontal_spacing, flow.style.vertical_align = 4, "center"
    return flow
  end
  local focus = pair("ssk_selection_focus")
  focus.add{type="sprite-button", style="tool_button", sprite="utility/right_arrow",
    tooltip=Loc("sankey-open-material-in-focus"), tags={ssk_ui="sankey_material_tab", target="focus", key=key}}
  small(focus, Loc("ui-focus")).style.font = "default-small"
  local balance = pair("ssk_selection_balance")
  balance.add{type="sprite-button", style="tool_button", sprite="utility/list_view",
    tooltip=Loc("sankey-open-material-in-balance"), tags={ssk_ui="sankey_material_tab", target="balance", key=key}}
  small(balance, Loc("ui-balance")).style.font = "default-small"
  local machines = pair("ssk_selection_machines")
  machine_action(machines, key)
  small(machines, Loc("sankey-selection-machines")).style.font = "default-small"
end

local function selection_controls(parent, n, us, player, width)
  local function section(name, caption)
    local flow = parent.add{type="flow", name=name, direction="vertical"}
    flow.style.vertical_spacing = 4
    flow.add{type="label", style="caption_label", caption=caption}
    return flow
  end
  local layout = section("ssk_selection_layout", Loc("sankey-selection-layout"))
  local row = option_row(layout)
  if us.layout == "lanes" then
    button(row, "▲", "up", Loc("sankey-move-up-shift-to-top-at-the"))
    button(row, "▼", "down", Loc("sankey-move-down-shift-to-bottom-at-the"))
  end
  button(row, Loc("sankey-hide"), "hide", Loc("sankey-hide-this-node-its-flow-becomes-stubs"))
  if n.kind == "group" then
    button(row, Loc("sankey-expand-group"), "expand", Loc("sankey-show-this-group-s-members-and-their"), { gid = n.group })
  elseif not n.base then
    button(row, Loc("sankey-collapse-group"), "collapse", Loc("sankey-merge-all-visible-members-of-this-group"), { gid = n.group })
  end
  if n.base then
    hint(layout, Loc("sankey-raw-input-split-per-lane-untick-split"), width)
  elseif n.kind ~= "group" then
    local divider = parent.add{type="line", name="ssk_selection_group_divider"}
    divider.style.width, divider.style.top_margin, divider.style.bottom_margin = width, 2, 2
    local grouping = section("ssk_selection_grouping", Loc("sankey-selection-grouping"))
    row = option_row(grouping)
    local gitems, gsel = {}, 1
    us.group_ids = {}
    for i, g in ipairs(Gr.list(player.index)) do
      gitems[i] = Loc.join(g.super_name, " › ", g.name)
      us.group_ids[i] = g.id
      if g.id == n.group then gsel = i end
    end
    local picker = row.add{type="drop-down", items=gitems, selected_index=gsel, tags={ssk_sk="move_group"},
      tooltip=Loc("sankey-move-to")}
    picker.style.width = width
    row = option_row(grouping)
    local tf = row.add{type="textfield", name="ssk_newgroup", tooltip=Loc("sankey-new-group-name")}
    tf.style.width = width - 72
    button(row, Loc("sankey-new-group"), "new_group", Loc("sankey-create-a-group-with-this-name-and"))
    button(row, Loc("sankey-default-group"), "ungroup", Loc("sankey-remove-your-override-for-this-item"))
  end
end

local function build_toolbar(bar, us, player)
  if us.view == "focus" then return focus_toolbar(bar, us, player) end
  local r1 = toolbar_strip(bar)
  local compact_filters = us.oversized and us.toolbar_width < 1000

  small(r1, Loc("sankey-view"))
  local view_picker = r1.add { type = "drop-down", items = { Loc("sankey-grouped-unfinished"), Loc("sankey-item-fluid-names") },
    selected_index = us.view == "overview" and 1 or 2, tags = { ssk_sk = "view" },
    tooltip = Loc("sankey-individual-item-and-fluid-names-are-the") }
  view_picker.style.width = compact_filters and 88 or 160
  local presets = View.presets()
  local items, sel = {}, 1
  for i, p in ipairs(presets) do
    items[i] = p.name
    if p.id == us.preset then sel = i end
  end
  us.preset_ids = {}
  for i, p in ipairs(presets) do us.preset_ids[i] = p.id end
  small(r1, Loc("sankey-preset"))
  local preset_picker = r1.add { type = "drop-down", items = items, selected_index = sel, tags = { ssk_sk = "preset" } }
  preset_picker.style.width = compact_filters and 104 or 190

  local middle = r1.add { type = "flow", name = "ssk_toolbar_middle", direction = "horizontal" }
  middle.style.minimal_width = 16
  middle.style.horizontal_align = "center"
  middle.style.horizontally_stretchable = true
  middle.style.horizontally_squashable = true
  local notice = middle.add { type = "label", name = "ssk_size_notice", visible = false }
  notice.style.single_line = true
  notice.style.horizontally_squashable = true

  local actions = right_group(r1, us, true)
  if us.view == "overview" then button(actions, Loc("sankey-collapse-overview"), "overview_reset", Loc("sankey-unfinished-grouping-return-expanded-groups-to-the")) end
  local nh = 0
  for _ in pairs(us.hidden) do nh = nh + 1 end
  if nh > 0 then button(actions, Loc("sankey-show-hidden", nh), "unhide_all") end
  zoom_buttons(actions, false, us.render_zoom or 1)
  label_toggle(actions, us)
  settings_button(actions, us)
  return r1
end

local function update_size_notice(notice, budget)
  notice.visible = budget ~= nil
  if not budget then return end
  notice.caption = Loc(budget.bypass and "sankey-size-unlimited" or "sankey-size-limited")
  notice.tooltip = Loc("sankey-size-summary", budget.nodes, budget.links)
end

---------------------------------------------------------------------------
-- canvas
---------------------------------------------------------------------------
local POLY -- polygon painter while drawing with the camera renderer (nil = sprites)

local function bg(canvas, color, x, y, w, h, kind_, tooltip)
  if POLY then return POLY.rect(x, y, w, h, Canvas.col(color, kind_ == "bg" and 0.10 or 0.35)) end
  local e = add_sprite(canvas, string.format("ssk-%s-c%02d", kind_, color), tooltip)
  place(e, x, y, w, h)
  return e
end

-- Labels and buttons can end up a few px taller/shorter than asked, which would shift every
-- element placed after them. So they are drawn LAST, each inside a fixed-size wrapper flow.
local function wrapped(canvas, x, y, w, h, spec)
  local f = canvas.add { type = "flow", direction = "horizontal" }
  place(f, x, y, w, h)
  f.style.padding = 0
  local e = f.add(spec)
  e.style.top_margin = 0
  e.style.maximal_width = w
  return e
end

local function ribbon_sprite(r, color)
  if r.kind == "bar" then return S.bar(color) end
  if r.kind == "elbow" then return S.elbow_name(r.corner, r.k, color) end
  return S.pick(r.dir, r.k, color, r.box_h)
end

local function selected_chain(paths, key)
  local upstream, downstream = {}, {}
  local function walk(set, reverse)
    set[key] = true
    local changed = true
    while changed do
      changed = false
      for _, path in ipairs(paths or {}) do
        local a, b = reverse and path.to or path.from, reverse and path.from or path.to
        if set[a] and not set[b] then set[b] = true; changed = true end
      end
    end
  end
  walk(upstream, true); walk(downstream, false)
  return {upstream=upstream, downstream=downstream}
end

local function chain_contains(chain, key)
  return chain.upstream[key] or chain.downstream[key]
end

local function chain_contains_link(chain, from, to)
  return (chain.upstream[from] and chain.upstream[to]
    or chain.downstream[from] and chain.downstream[to]) == true
end

local function highlight(st, key)
  -- Balance is already scoped to the selected material. Keep its colours
  -- visible while hovering or pinning a neighbour.
  if not st.dim_nodes then key = nil end
  local chain
  if key then
    st.chains = st.chains or {}
    chain = st.chains[key]
    if not chain then
      chain = selected_chain(st.paths, key)
      st.chains[key] = chain
    end
  end
  for _, r in ipairs(st.ribbons) do
    local dim = chain ~= nil and not chain_contains_link(chain, r.from, r.to)
    if r._dimmed ~= dim then
      r._dimmed = dim
      -- Keep the darker flow shade at joins so highlighted material bars stay distinct.
      local c = dim and palette.DIM or palette.muted(r.color)
      if r.ro then
        if r.ro.valid then r.ro.color = Canvas.col(c) end
      elseif r.elem and r.elem.valid then r.elem.sprite = ribbon_sprite(r, c) end
    end
  end
  for node_key, node in pairs(st.node_visuals or {}) do
    local dim = chain ~= nil and not chain_contains(chain, node_key)
    if node.dimmed ~= dim then
      node.dimmed = dim
      for _, sprite in ipairs(node.sprites) do
        if sprite.element.valid then sprite.element.sprite = dim and (sprite.dim or S.bar(palette.DIM)) or sprite.original end
      end
      for _, shape in ipairs(node.shapes) do
        if shape.object.valid then
          shape.object.color = dim and Canvas.col(palette.DIM, shape.alpha * palette.dim.alpha)
            or Canvas.col(shape.color, shape.alpha)
        end
      end
      if node.icon and node.icon.valid then node.icon.style.draw_grayscale_picture = dim or node.grayscale end
      for _, label in ipairs(node.labels) do
        if label.element.valid then label.element.style.font_color = dim and {0.4, 0.4, 0.4} or label.original end
      end
    end
  end
  return chain
end

local RETURN_MARKER_SIZE = 12
local RETURN_MARKER_SPACING = RETURN_MARKER_SIZE * 5
local RETURN_ARROW_SIZE = 14

local function draw_return_markers(canvas, y, stops, zoom)
  local positions, sources_right, targets_right = {}, 0, 0
  for x, stop in pairs(stops) do
    positions[#positions + 1] = x
    if stop.source then sources_right = sources_right + 1 end
    if stop.target then targets_right = targets_right + 1 end
  end
  table.sort(positions)
  local sources_left, targets_left = 0, 0
  for i = 1, #positions - 1 do
    local x = positions[i]
    local stop = stops[x]
    if stop.source then sources_left, sources_right = sources_left + 1, sources_right - 1 end
    if stop.target then targets_left, targets_right = targets_left + 1, targets_right - 1 end
    local left = sources_right > 0 and targets_left > 0
    local right = sources_left > 0 and targets_right > 0
    local length = positions[i + 1] - x
    -- Shared segments with traffic in both directions keep a plain line.
    if left ~= right and length >= 2 * RETURN_MARKER_SPACING then
      local count = math.floor(length / RETURN_MARKER_SPACING)
      local first = x + (length - (count - 1) * RETURN_MARKER_SPACING) / 2
      local sprite = left and "utility/backward_arrow" or "utility/forward_arrow"
      for j = 1, count do
        local marker = add_sprite(canvas, sprite)
        marker.ignored_by_interaction = true
        marker.tags = { ssk_return_direction = left and "left" or "right" }
        local center = first + (j - 1) * RETURN_MARKER_SPACING
        place(marker, (center - RETURN_MARKER_SIZE / 2) * zoom, (y + 1 - RETURN_MARKER_SIZE / 2) * zoom,
          RETURN_MARKER_SIZE * zoom, RETURN_MARKER_SIZE * zoom)
      end
    end
  end
end

local function draw_returns(canvas, L, late, width, show_markers, zoom)
  for i, route in ipairs(L.returns or {}) do
    local y = L.return_y + (i - 1) * 28
    local origin = route.sources[1]
    local sprite = S.return_line(origin.color or origin.ginfo.color)
    local function line(x, top, w, h)
      local element = add_sprite(canvas, sprite)
      element.ignored_by_interaction = true
      place(element, x * zoom, top * zoom, w * zoom, h * zoom)
    end
    local offset = 10 + 4 * ((i - 1) % 5)
    local first, last = math.huge, 0
    local stops = show_markers and {}
    local function stop_at(x, kind)
      if not stops then return end
      x = round(x)
      stops[x] = stops[x] or {}
      stops[x][kind] = true
    end
    for _, n in ipairs(route.sources) do
      local source_x, source_y = n.x + View.NODE_W, n.y + n.h / 2
      local from = source_x + offset
      line(source_x, source_y, offset, 2)
      line(from, source_y, 2, y - source_y + 2)
      stop_at(from, "source")
      first, last = math.min(first, from), math.max(last, from)
    end
    local destination = route.targets[1].node
    local recipe = route.recipe and localised_name({ key = route.recipe, kind = "recipe" })
    local caption = route.fuel and Loc("cells-fuel-return", localised_name(origin), fmt(route.rate))
      or recipe and Loc("sankey-return-recipe", recipe)
      or route.catalyst and Loc("sankey-return-catalyst", localised_name(origin))
      or Loc("sankey-return-flow", localised_name(origin), localised_name(destination))
    for _, user in ipairs(route.targets) do
      local consumer = user.node
      local x, target_y = consumer.x - offset, user.target_y or (consumer.y + consumer.h / 2)
      line(x, target_y, 2, y - target_y + 2)
      line(x, target_y, offset, 2)
      local material = (route.recipe or origin.kind == "recipe") and consumer or origin
      local tooltip = route.fuel and Loc("cells-fuel-return", localised_name(origin), fmt(user.rate))
        or Loc.join(caption, "\n", Loc("sankey-return-rate", localised_name(material), fmt(user.rate), units(material)))
      local arrow = add_sprite(canvas, "utility/forward_arrow", tooltip)
      -- The vanilla sprite's point ends before its transparent right edge.
      -- Align the visible point with the bar, which is drawn over the padding.
      place(arrow, (consumer.x - 9) * zoom, (target_y + 1 - RETURN_ARROW_SIZE / 2) * zoom,
        RETURN_ARROW_SIZE * zoom, RETURN_ARROW_SIZE * zoom)
      stop_at(x, "target")
      first, last = math.min(first, x), math.max(last, x)
    end
    line(first, y, last - first + 2, 2)
    if stops then draw_return_markers(canvas, y, stops, zoom) end
    late[#late + 1] = { first + 2, y + 5, math.min(360, width / zoom - first - 4), 18,
      { type = "label", caption = caption, tooltip = route.fuel and Loc("cells-fuel-cold-start") or caption,
        tags = route.fuel and { ssk_cell_fuel = origin.key }
          or { ssk_loop_return = route.recipe or origin.key } },
      font = "default-small" }
  end
end

local function draw(canvas, L, us, st, player, W, H, zoom, recipe_icons, read_balance, detailed_ribbons)
  st.ribbons = {}
  st.node_visuals = {}
  st.chains = nil
  st.dim_nodes = not us.neighborhood
  st.selected = us.view == "focus" and us.focus or us.sel
  if us.neighborhood then st.selected=us.pinned end
  local count = 0
  local cx = L.col_x
  local late = {} -- deferred labels / buttons
  local balance_tooltips = {}
  local detailed = zoom >= 0.8
  st.display_zoom = zoom
  local function put(e, x, y, w, h)
    place(e, x * zoom, y * zoom, w * zoom, h * zoom)
  end
  local scale = player and player.display_scale or 1
  local function connected_bar(e, x, y, w, h)
    local sx, sy, sw, sh = Geometry.box(x * zoom, y * zoom, w * zoom, h * zoom)
    place(e, sx, sy, Geometry.sprite_span(sx, sw, scale), sh)
  end
  local function rect(x, y, w, h, color)
    return POLY.rect(x * zoom, y * zoom, w * zoom, h * zoom, color)
  end
  local function backdrop(color, x, y, w, h, kind_, tip)
    return bg(canvas, color, x * zoom, y * zoom, w * zoom, h * zoom, kind_, tip)
  end
  POLY = nil
  if player then Canvas.clear(player.index) end
  if us.renderer == "poly" and player then
    POLY = Canvas.begin(player, W, H)
    local cam = canvas.add(Canvas.camera_spec(player, POLY))
    place(cam, 0, 0, W, H)
    cam.ignored_by_interaction = true
  else
    local background = add_sprite(canvas, "ssk-plot-background")
    background.parent.ignored_by_interaction = true
    place(background, 0, 0, W, H)
  end

  -- 1. lanes and sub-lanes (behind everything)
  for _, ln in ipairs(L.lane_list) do
    local x0 = cx[ln.c0] - View.LANE_LEFT
    local x1 = cx[ln.c1] + View.NODE_W + View.LANE_RIGHT
    backdrop(ln.color, x0, ln.y0, x1 - x0, ln.h, "bg", ln.name)
    backdrop(ln.color, x0, ln.y0, 4, ln.h, "line", ln.name)
    late[#late + 1] = { x0 + 10, ln.y0 + 2, 220, 20, { type = "label", caption = ln.name, ignored_by_interaction = true },
                        font = "default-bold", color = { 0.85, 0.85, 0.85 } }
    count = count + 2
    if ln.titled then
      for _, sb in ipairs(ln.sub_list) do
        local sx0 = cx[sb.c0] - View.LANE_LEFT + 10
        local sx1 = cx[sb.c1] + View.NODE_W + View.LANE_RIGHT - 10
        backdrop(ln.color, sx0, sb.y0, sx1 - sx0, sb.h, "bg", Loc.join(ln.name, " › ", sb.name))
        backdrop(ln.color, sx0, sb.y0, sx1 - sx0, 1, "line")
        late[#late + 1] = { sx0 + 4, sb.y0 + 1, 200, 14, { type = "label", caption = sb.name, ignored_by_interaction = true },
                            font = "default-small", color = { 0.75, 0.75, 0.75 } }
        count = count + 2
      end
    end
  end

  -- 2. Shared route primitives; backend selection cannot change the route.
  st.paths = {}
  local meshes, mesh_order, tooltips, hover = {}, {}, {}, {}
  local function ribbon_color(link)
    local src, dst = link.a, link.b
    local endpoint
    if src.is_cell or dst.is_cell then
      endpoint = src.is_cell and dst or src
    else
      endpoint = us.color_mode ~= "source" and dst or src
    end
    return endpoint.color or endpoint.ginfo.color
  end
  local function ribbon(l, xa, xb, color)
    local route = Geometry.route(l, xa, xb, l.y1, l.y2)
    local link = l.link or l
    st.paths[#st.paths + 1] = { from=l.from, to=l.to, pieces=route, color=color, weight=link.w }
    local pieces = route
    if zoom ~= 1 then
      pieces = {}
      for _, piece in ipairs(route) do pieces[#pieces + 1] = Geometry.scaled_piece(piece, zoom) end
    end
    if detailed_ribbons or link.transport then
      if not tooltips[link] then tooltips[link] = ribbon_tooltip(link, recipe_icons) end
      hover[#hover + 1] = { pieces = pieces, tip = tooltips[link], from = l.from, to = l.to,
        tags=link.transport and transport_tags(link.transport) }
    end
    if POLY then
      local key = Loc.join(l.from, ">", l.to)
      if not meshes[key] then
        meshes[key] = { from = l.from, to = l.to, color = color, pieces = {} }
        mesh_order[#mesh_order + 1] = key
      end
      for _, p in ipairs(pieces) do table.insert(meshes[key].pieces, p) end
      return
    end
    for _, p in ipairs(pieces) do
      local r = { kind = p.kind, corner = p.corner, dir = p.dir, k = p.k, box_h = p.box_h,
        color = color, from = l.from, to = l.to }
      r.elem = add_sprite(canvas, ribbon_sprite(r, color))
      r.elem.ignored_by_interaction = true
      place(r.elem, p.x, p.y, Geometry.sprite_size(p, scale))
      if r.ro or r.elem then st.ribbons[#st.ribbons + 1] = r end
    end
  end
  for _, sg in ipairs(L.segments or {}) do
    local x1 = sg.a.kind == "via" and sg.a.x or sg.a.x + (sg.a.width or View.NODE_W)
    if sg.b.x > x1 then
      ribbon(sg, x1, sg.b.x, ribbon_color(sg.link))
      count = count + 1
    end
  end
  for _, l in ipairs(L.segments and {} or L.links) do
    local x1, x2 = l.a.x + View.NODE_W, l.b.x
    if x2 > x1 then
      ribbon(l, x1, x2, ribbon_color(l))
      count = count + 1
    end
  end
  for _, key in ipairs(mesh_order) do
    local r = meshes[key]
    r.ro = POLY.ribbon(r.pieces, Canvas.col(r.color))
    st.ribbons[#st.ribbons + 1] = r
  end
  for _, target in ipairs(hover) do
    Tooltip.ribbon(canvas, target.pieces, target.tip, target.tags or { ssk_sk = "ribbon", from = target.from, to = target.to }, nil,
      function(spec, x, y, w, h)
        local hit = wrapped(canvas, x, y, w, h, spec)
        hit.style.width, hit.style.height = w, h
      end)
  end
  local markers = player and player.mod_settings["ssk-return-direction-markers"]
  draw_returns(canvas, L, late, W, markers and markers.value, zoom)
  -- 3. stubs + node bars (sprites); buttons and labels deferred
  for _, col in ipairs(L.cols) do
    for _, n in ipairs(col) do
      local visual = { sprites = {}, shapes = {}, labels = {}, dimmed = false }
      st.node_visuals[n.key] = visual
      local function stub(x, y, h, tip)
        local width = View.STUB / #palette.stub_alpha
        local right = x > n.x
        for step, alpha in ipairs(palette.stub_alpha) do
          local offset = right and (step - 1) * width or View.STUB - step * width
          if POLY then
            local object = rect(x + offset, y, width, h, Canvas.col(palette.GREY, alpha))
            if object then visual.shapes[#visual.shapes + 1] = { object=object, color=palette.GREY, alpha=alpha } end
          else
            local sx, sy, sw, sh = Geometry.box((x + offset) * zoom, y * zoom, width * zoom, h * zoom)
            if sw > 0 and sh > 0 then
              local name = S.stub(step)
              local e = add_sprite(canvas, name)
              e.parent.ignored_by_interaction = true
              place(e, sx, sy, Geometry.sprite_span(sx, sw, scale), sh)
              visual.sprites[#visual.sprites + 1] = { element=e, original=name, dim=S.stub(step, true) }
            end
          end
        end
        put(add_sprite(canvas, "ssk-node-hit", tip), x, y, View.STUB, h)
      end
      local lab_use = n.lab_use or 0
      local other_use = n.stub_out - lab_use
      local lab_tip = lab_use > 0 and (Loc("sankey-labs-estimated-s", fmt(lab_use)))
      if n.stub_out > 0 then
        local use_tip = lab_tip and (Loc("sankey-estimated-from-consumption-outside-recorded-recipes", lab_tip))
          or Loc("sankey-other-uses-of-s-not-shown-outside", display_name(n), fmt(n.stub_out))
        if lab_tip and other_use > 1e-4 then use_tip = Loc("sankey-other-uses-s", use_tip, fmt(other_use)) end
        local stub_x = n.x + View.NODE_W
        stub(stub_x, n.stub_out_y, n.t_stub_out, use_tip)
        count = count + 1
      end
      if n.stub_in > 0 then
        stub(n.x - View.STUB, n.stub_in_y, n.t_stub_in, Loc("sankey-other-sources-of-s-outside-this-view", display_name(n), fmt(n.stub_in)))
        count = count + 1
      end
      local tip = {}
      tip[#tip + 1] = Loc.join(rt(sprite_for(n)), " ", display_name(n), "  [", n.ginfo.super_name, " › ", n.ginfo.name, "]  ", View.tier_label(n.tier), (n.era and Loc.join(" ", Loc("sankey-tech-era", string.format("%d", n.era))) or Loc.join(" ", Loc("sankey-production-depth-2"))))
      if n.context then tip[#tip + 1] = n.context end
      if n.note then tip[#tip + 1] = n.note end
      if n.kind == "item" or n.kind == "fluid" or n.kind == "group" then
        tip[#tip + 1] = Loc("sankey-produced-consumed", fmt(n.prod), units(n), fmt(n.cons), units(n))
        if n.kind == "group" then tip[#tip + 1] = Loc("sankey-totals-across-these-members-expand-the-group") end
      end
      if n.copies and n.copies > 1 then
        tip[#tip + 1] = Loc("sankey-split-input-this-copy-feeds-with-s", n.ginfo.super_name, fmt(n.sout), string.format("%.0f", (n.share or 0) * 100), fmt(n.total_prod or n.prod), string.format("%d", n.copies))
      end
      if n.stub_in > 0 then tip[#tip + 1] = Loc("sankey-other-sources-s", fmt(n.stub_in)) end
      if lab_tip then tip[#tip + 1] = lab_tip end
      if other_use > 1e-4 then tip[#tip + 1] = Loc("sankey-other-uses-s-2", fmt(other_use)) end
      if (n.catalyst or 0) > 0 then tip[#tip + 1] = Loc("sankey-catalyst-consumed-and-returned-netted-out-s", fmt(n.catalyst)) end
      local loop_badge = false
      for _, lp in ipairs(n.loops) do
        if not lp.routed then
          loop_badge = true
          local what = rt(base_key(lp.what))
          if lp.back and lp.out then
            tip[#tip + 1] = Loc("sankey-feeds-back-s-into-loop-not-drawn", fmt(lp.rate), what)
          elseif lp.back then
            tip[#tip + 1] = Loc("sankey-gets-s-back-from-loop-not-drawn", fmt(lp.rate), what)
          elseif lp.late then
            tip[#tip + 1] = Loc("sankey-s-later-tech-producer-not-drawn", what, fmt(lp.rate))
          else
            tip[#tip + 1] = Loc("sankey-s-recycling-reversing-recipe-not-drawn", what, fmt(lp.rate))
          end
        end
      end
      if n.members then
        local parts = {}
        for _, mk in ipairs(n.members) do parts[#parts + 1] = rt(mk) end
        tip[#tip + 1] = Loc("sankey-members", Loc.join_list(parts, " "))
      end
      local details = Loc.join_list(tip, "\n")
      local shown = (n.prod > 0) and n.prod or n.cons
      local rate = n.rate_line or n.caption and n.context or n.kind == "recipe" and Loc("machine-status-recipe") or (Loc.join(fmt(shown), " ", units(n)))
      local usage = not n.transport and us.neighborhood and n.selected_usage
      if usage then
        local material=L.nodes[us.focus]
        rate=Loc.join(fmt(usage), " ", units(material))
        details=Loc("sankey-consumes-selected", display_name(material), rate, details)
      end
      local tooltip = { "", rt(sprite_for(n)), " ", localised_name(n), "\n", rate }
      if n.note then tooltip[#tooltip + 1] = Loc.join("\n", n.note) end
      if usage then
        tooltip[#tooltip+1]=Loc.join(" ", Loc("selected-material-consumed", localised_name(L.nodes[us.focus])))
        if n.kind~="recipe" then tooltip[#tooltip+1]=Loc("sankey-consumer-production", fmt(n.prod), units(n)) end
      end
      if not n.transport then
        if read_balance and (n.kind == "item" or n.kind == "fluid") then
          local key = material_key(n)
          if not balance_tooltips[key] then
            local row = read_balance(key)
            balance_tooltips[key] = BalanceUI.hover_details(row.prod, row.cons, units(n), row)
          end
          tooltip[#tooltip + 1] = Loc.join("\n\n", balance_tooltips[key])
        elseif n.kind == "item" or n.kind == "fluid" or n.kind == "group" then
          local rates = BalanceUI.hover_details(n.total_prod or n.prod, n.total_cons or n.cons, units(n))
          if n.kind == "group" then
            rates = Loc.join(rates, "\n", Loc("sankey-totals-across-these-members-expand-the-group"))
          end
          tooltip[#tooltip + 1] = Loc.join("\n\n", rates)
        end
      end
      if lab_tip then tooltip[#tooltip + 1] = Loc.join("\n", lab_tip) end
      local pin_key = not n.transport and (not us.is_cell_chart or L.details) and material_key(n)
      if pin_key then
        local docked = us.view ~= "focus" and not us.neighborhood and not us.is_cell_chart
        if docked then tooltip[#tooltip + 1] = Loc.join("\n\n", Loc("sankey-rate-card-click")) end
        tooltip[#tooltip + 1] = Loc.join(docked and "\n" or "\n\n", Loc("rate-card-alt-click"))
      end
      local recipe_info
      if L.details and not n.transport and not n.is_cell then
        if n.kind == "recipe" then
          recipe_info = RecipeDetails.recipe(L.details, base_key(n.key):sub(8), fmt)
        elseif n.kind == "item" or n.kind == "fluid" then
          recipe_info = RecipeDetails.material(L.details, base_key(n.key), fmt, 2, recipe_icons)
        end
      end
      local breakdown = recipe_summary(n, 3, recipe_icons)
      if #breakdown > 0 then
        breakdown = Loc.join("\n\n", Loc.join_list(breakdown, "\n"))
        if not recipe_info then tooltip[#tooltip + 1] = breakdown end
        details = Loc.join(details, breakdown)
      end
      local imports=external_supply(n)
      if imports then
        -- Preserve the selected-material rate and usage positions in the hover.
        tooltip[#tooltip + 1] = "\n\n"
        tooltip[#tooltip + 1] = imports
        details=Tooltip.lines({details,"\n\n",imports})
      end
      if recipe_info then
        tooltip[#tooltip+1]="\n\n"
        tooltip[#tooltip+1]=recipe_info
        details=Tooltip.lines({details,"\n\n",recipe_info})
      end
      if n.transport then
        tooltip=transport_tooltip(n.transport,true)
        details=tooltip
        rate=Loc.join(fmt(n.transport.rate)," ",Loc("history-items-s"))
      end
      local function node_bar(x, y, width, height, color, caption, tags)
        local bar
        if POLY then
          local object = rect(x, y, width, height, Canvas.col(color, 1))
          if object then visual.shapes[#visual.shapes + 1] = { object=object, color=color, alpha=1 } end
          bar = add_sprite(canvas, "ssk-node-hit", caption)
        else
          bar = add_sprite(canvas, S.bar(color), caption)
          visual.sprites[#visual.sprites + 1] = { element=bar, original=bar.sprite }
        end
        if POLY then put(bar, x, y, width, height) else connected_bar(bar, x, y, width, height) end
        bar.raise_hover_events = true
        bar.tags = tags
        count = count + 1
      end
      local bar_tags = n.transport and transport_tags(n.transport,n,us)
        or { ssk_sk = "node", key = n.key, fx = (us.view == "focus"), part = "bar", ssk_card_material = pin_key or nil }
      if n.is_cell then
        local half = n.width / 2
        local function stack(segments, side, x)
          if #segments == 0 then
            node_bar(x, n.y, half, n.h, palette.GREY, tooltip, bar_tags)
          end
          for _, sg in ipairs(segments) do
            local link = sg.link
            local material = side == "inputs" and link.a or link.b
            local edge = side == "inputs" and sg.y2 or sg.y1
            local center = edge + sg.t / 2
            local height = sg.cell_band_h
            local sprite = sprite_for(material)
            local band_tip = tooltips[link] or ribbon_tooltip(link, recipe_icons)
            local tags = { ssk_sk = "node", key = n.key, part = "bar", side = side, cell_material = sprite }
            node_bar(x, center - height / 2, half, height, ribbon_color(link), band_tip, tags)
            local size = View.CELL_ICON
            late[#late + 1] = { x + (half - size) / 2, center - size / 2, size, size,
              { type = "sprite-button", style = "slot_button", sprite = sprite, tooltip = band_tip, raise_hover_events = true,
                tags = { ssk_sk = "node", key = n.key, part = "icon", side = side, cell_material = sprite } }, fill = true }
          end
        end
        local in_segs = n.fins
        if n.return_fins then
          in_segs = {}
          for _, sg in ipairs(n.fins) do in_segs[#in_segs + 1] = sg end
          for _, sg in ipairs(n.return_fins) do in_segs[#in_segs + 1] = sg end
        end
        stack(in_segs, "inputs", n.x)
        stack(n.fouts, "outputs", n.x + half)
        local label_w = L.label_w[n.ci]
        local compact_label = not detailed and us.keep_cell_labels and us.show_labels
        local label_y = compact_label and math.max(0, n.y - 13 / zoom) or n.top
        local label_h = compact_label and 12 / zoom or 18
        late[#late + 1] = { n.x + (n.width - label_w) / 2, label_y, label_w, label_h,
          { type = "label", style = "caption_label", caption = n.cell_name, tooltip = tooltip,
            tags = { ssk_label = n.key } }, align = "center", node_label = n.key,
          keep = compact_label, font = compact_label and "default-tiny-bold" or nil }
      else
        node_bar(n.x, n.y, View.NODE_W, n.h, n.color or n.ginfo.color, tooltip, bar_tags)
      local iy = n.y - View.NODE_W - View.ICON_GAP
      local label_w = math.min(260, (L.label_w and L.label_w[n.ci]) or 260)
      if not detailed then
        local selected = n.key == st.selected
        local height = selected and 18 or 12
        local width = math.min(W, selected and 116 or math.floor(label_w * zoom))
        local header = n.y - (n.top or (iy - 18))
        if selected or (us.show_labels and width >= 28 and header * zoom >= height + 1) then
          local x = math.min(n.x * zoom, W - width) / zoom
          local y = math.max(0, n.y * zoom - height - (selected and 0 or 1)) / zoom
          late[#late + 1] = { x, y, width / zoom, height / zoom,
            {type="label", caption=localised_name(n), ignored_by_interaction=true, tags={ssk_label=n.key}},
            font=selected and "default-small-bold" or "default-tiny-bold", keep=true, node_label=n.key }
        end
      end
      if detailed then
        local stem = add_sprite(canvas, S.bar(n.color or n.ginfo.color))
        visual.sprites[#visual.sprites + 1] = { element=stem, original=stem.sprite }
        put(stem, n.x + View.NODE_W / 2 - 1, iy + View.NODE_W, 2, View.ICON_GAP)
        stem.ignored_by_interaction = true
        late[#late + 1] = { n.x, iy, View.NODE_W, View.NODE_W,
          { type = "sprite-button", sprite = sprite_for(n), tooltip = tooltip, style = "slot_button",
            raise_hover_events = true, tags = n.transport and transport_tags(n.transport,n,us) or
              { ssk_sk = "node", key = n.key, fx = (us.view == "focus"), ssk_card_material = pin_key or nil } },
          toggled = (us.sel == n.key), fill = true, node_icon=n.key }
      end
      local show_label = us.show_labels or n.key == us.sel or n.key == us.pinned
        or n.kind == "group" or n.transport~=nil
        or (us.view == "focus" and base_key(n.key) == us.focus)
      if detailed and L.label_above then
        late[#late + 1] = { n.x, n.top or (iy - 18), label_w, 16,
          { type = "label", caption = localised_name(n), tooltip = details,
            visible = show_label == true, tags = { ssk_label = n.key } },
          font = "default-small-bold", node_label=n.key }
        if usage or (n.kind ~= "recipe" and n.kind ~= "group") then
          local rate_w = math.max(1, label_w - View.NODE_W - 6)
          late[#late + 1] = { n.x + View.NODE_W + 6, iy + 8, rate_w, 16,
            { type = "label", caption = rate,
              visible = show_label == true, ignored_by_interaction = true, tags = { ssk_rate = n.key } },
            font = "default-small", color = { 0.75, 0.75, 0.75 }, node_label=n.key }
        end
      elseif detailed then
        late[#late + 1] = { n.x + View.NODE_W + 3, iy + 6, 80, 16,
          { type = "label", caption = rate, tooltip = details, visible = show_label == true,
            tags = { ssk_label = n.key } }, font = "default-small-bold", node_label=n.key }
      end
      if detailed and loop_badge then
        late[#late + 1] = { n.x - 18, iy + 4, 18, 20, { type = "label", caption = "↺", ignored_by_interaction = true }, font = "default-bold", node_label=n.key }
      end
      end
    end
  end

  -- 4. column headers
  for ci, t in ipairs(L.col_tiers) do
    local heading = L.column_labels and L.column_labels[t] or View.tier_label(t)
    if us.neighborhood then
      local center = L.center_ci or 2
      local material=us.focus and localised_name({key=us.focus,kind=us.focus:match("^(%a+)/")}) or Loc("sankey-selected-material")
      heading = ci == center and Loc("sankey-selected-material-2") or ci > center and Loc("uses-material-heading", material)
        or ci == center - 1 and Loc("sankey-materials") or Loc("sankey-inputs-2", (center - ci))
    end
    late[#late + 1] = { cx[ci], 6, (us.neighborhood or L.column_labels) and L.label_w[ci] or 60, us.neighborhood and 40 or 18,
      { type = "label", caption = heading, tooltip=heading, tags={ssk_column=us.neighborhood and ci>(L.center_ci or 2) and "uses" or "other"} },
      single_line=not us.neighborhood, font = "default-small-bold", color = { 0.6, 0.6, 0.6 } }
  end

  -- 5. deferred labels / buttons, each in a fixed-size wrapper
  for _, d in ipairs(late) do
    if detailed or d.keep then
      local x, y, w, h = Geometry.box(d[1] * zoom, d[2] * zoom, d[3] * zoom, d[4] * zoom)
      w, h = math.max(1, w), math.max(1, h)
      local e = wrapped(canvas, x, y, w, h, d[5])
      if d.keep then e.parent.ignored_by_interaction = true end
      if d.font then e.style.font = not d.keep and zoom < 1 and "default-tiny-bold" or zoom > 1.25 and "default-bold" or d.font end
      if d.color then e.style.font_color = d.color end
      if d.align then e.style.horizontal_align = d.align end
      if d.fill or d[5].type == "label" then e.style.width, e.style.height = w, h end
      if d[5].type == "label" then e.style.single_line = d.single_line~=false end
      if d.toggled then e.toggled = true end
      if d.node_icon then
        local visual = st.node_visuals[d.node_icon]
        visual.icon, visual.grayscale = e, e.style.draw_grayscale_picture == true
        visual.icon_bounds = {x, y, x + w, y + h}
      elseif d.node_label then
        local visual = st.node_visuals[d.node_label]
        visual.labels[#visual.labels + 1] = { element=e, original=e.style.font_color or {1, 1, 1} }
      end
      count = count + 1
    end
  end
  return count, highlight(st, st.selected)
end

local function render_overview(side, L, us, paths, chain, width, height, player, managed_scroll, overview_bands)
  local overview = side.ssk_overview
  if not overview then
    overview = side.add{type="frame", name="ssk_overview", style="inside_deep_frame", direction="vertical"}
    overview.style.padding = 8
    overview.add{type="label", style="caption_label", caption=Loc("sankey-chart-overview")}
    local map = overview.add{type="flow", name="ssk_overview_map", direction="vertical"}
    map.style.vertical_spacing = 0
    map.add{type="flow", name="ssk_overview_paths", direction="vertical", ignored_by_interaction=true}.style.vertical_spacing = 0
    map.add{type="flow", name="ssk_overview_nodes", direction="vertical"}.style.vertical_spacing = 0
  end
  overview.style.width = width
  overview.visible = next(L.nodes) ~= nil
  local map = overview.ssk_overview_map
  local ribbons, nodes = map.ssk_overview_paths, map.ssk_overview_nodes
  local map_w, map_h = width - 16, math.max(42, math.min(108, math.floor(height * 0.32)))
  map.style.width, map.style.height = map_w, map_h
  ribbons.style.width, ribbons.style.height, ribbons.style.bottom_margin = map_w, map_h, -map_h
  nodes.style.width, nodes.style.height = map_w, map_h
  if managed_scroll then
    nodes.style.bottom_margin = -map_h
    local outline = map.ssk_viewport_outline
    if not outline then
      outline = map.add{type="flow", name="ssk_viewport_outline", direction="vertical", ignored_by_interaction=true}
      outline.style.vertical_spacing = 0
      for _ = 1, 4 do place(add_sprite(outline, "ssk-plot-measured"), 0, 0, 1, 1) end
    end
    outline.style.width, outline.style.height = map_w, map_h
  end
  ribbons.clear()
  local selected = L.nodes[us.sel]
  local selected_key = selected and selected.key
  if not selected then chain = nil end
  if nodes.tags.key ~= selected_key then
    nodes.clear()
    nodes.tags = {key=selected_key}
  end
  local scale = math.min((map_w - 10) / math.max(1, L.content_w), (map_h - 10) / math.max(1, L.content_h))
  local ox, oy = (map_w - L.content_w * scale) / 2, (map_h - L.content_h * scale) / 2

  -- A visible but isolated selection has no bands to emphasize.
  if chain then
    local has_route = false
    for _, path in ipairs(paths) do
      if chain_contains_link(chain, path.from, path.to) then has_route = true; break end
    end
    if not has_route then chain = nil end
  end
  if overview_bands then
    local drawn = {}
    local function piece(shape, color)
      local p = Geometry.overview_piece(shape, scale, ox, oy, player.display_scale)
      local x, y, w, h = p.x, p.y, p.w, p.h
      local sprite = ribbon_sprite(p, color)
      local key = table.concat({sprite, x, y, w, h}, ":")
      if drawn[key] then return end
      drawn[key] = true
      local e = ribbons.add{type="sprite", sprite=sprite, resize_to_sprite=false, ignored_by_interaction=true}
      local style = e.style
      style.stretch_image_to_widget_size = true
      style.width, style.height = w, h
      style.left_margin, style.top_margin, style.bottom_margin = x, y, -h
      -- Cancel the height and offset separately to keep fractional scaling aligned.
      local reset = ribbons.add{type="empty-widget", ignored_by_interaction=true}
      reset.style.width, reset.style.height, reset.style.top_margin = 0, 0, -y
      reset.style.left_margin, reset.style.bottom_margin = 0, 0
    end
    local function draw_paths(emphasized)
      for _, path in ipairs(paths) do
        local related = chain ~= nil and chain_contains_link(chain, path.from, path.to)
        if related == emphasized then
          local color = related and path.color or chain and palette.OVERVIEW_DIM or palette.muted(path.color)
          for _, shape in ipairs(path.pieces) do piece(shape, color) end
        end
      end
    end
    draw_paths(false)
    for _, col in ipairs(L.cols) do
      for _, n in ipairs(col) do
        local color = palette.GREY
        if n.t_stub_in > 0 then
          piece({kind="bar", x=n.x-View.STUB, y=n.stub_in_y, w=View.STUB, h=n.t_stub_in}, color)
        end
        if n.t_stub_out > 0 then
          piece({kind="bar", x=n.x+View.NODE_W, y=n.stub_out_y, w=View.STUB, h=n.t_stub_out}, color)
        end
      end
    end
    if chain then draw_paths(true) end
  end
  local previous = {}
  local children = nodes.children
  for i = 1, #children, 2 do
    local widget = children[i].children[1]
    previous[widget.tags.key] = {widget=widget, reset=children[i + 1]}
  end
  local function dot(n, active)
    local old = previous[n.key]
    previous[n.key] = nil
    local dim = chain and not chain_contains(chain, n.key)
    local color = dim and palette.DIM or (n.color or n.ginfo.color)
    local sprite = S.bar(color)
    local e = old and old.widget or add_sprite(nodes, sprite, Loc("sankey-overview-jump", display_name(n)))
    if not old then e.tags = {ssk_sk="overview_jump", key=n.key}
    elseif e.sprite ~= sprite then e.sprite = sprite end
    local w = math.max(active and 6 or 3, View.NODE_W * scale)
    local h = math.max(active and 7 or 4, n.h * scale)
    local x = ox + (n.x + View.NODE_W / 2) * scale - w / 2
    local y = oy + (n.y + n.h / 2) * scale - h / 2
    place(e, x, y, w, h, old and old.reset)
  end
  for _, col in ipairs(L.cols) do
    for _, n in ipairs(col) do if n.key ~= us.sel then dot(n, false) end end
  end
  if selected then dot(selected, true) end
  for _, obsolete in pairs(previous) do
    obsolete.widget.parent.destroy()
    obsolete.reset.destroy()
  end
  return scale, ox, oy
end

local function clamp_pan(value, maximum)
  return math.max(0, math.min(round(value), maximum))
end

local SCROLLBAR = 12

local function scroll_track(parent, axis)
  local track = parent.add{type="flow", name="ssk_scroll_"..axis, direction="vertical"}
  track.style.vertical_spacing = 0
  for _, part in ipairs({"before", "after", "thumb"}) do
    local thumb = part == "thumb"
    local sprite = add_sprite(track, thumb and "ssk-scroll-thumb-"..axis or "ssk-plot-background")
    if thumb then
      sprite.raise_hover_events = true
      sprite.tags = {ssk_scroll_visual=axis}
    else sprite.tags = {ssk_scroll_axis=axis, ssk_scroll_page=part == "before" and -1 or 1} end
    place(sprite,0,0,1,1)
  end
end

local function update_track(track, axis, length, position, maximum)
  if not track then return end
  local horizontal = axis=="x"
  local style = track.style
  style.width, style.height = horizontal and length or SCROLLBAR, horizontal and SCROLLBAR or length
  local thumb_length = math.min(length, math.max(18, round(length * length / (length + maximum))))
  local travel = length - thumb_length
  local start = maximum > 0 and round(travel * position / maximum) or 0
  local children = track.children
  local function segment(index, offset, extent, inset)
    local wrapper, reset = children[index], children[index+1]
    local shown = maximum > 0 and extent > 0
    wrapper.visible, reset.visible = shown, shown
    local thickness = SCROLLBAR - 2 * inset
    if shown then
      local x, y = horizontal and offset or inset, horizontal and inset or offset
      local w, h = horizontal and extent or thickness, horizontal and thickness or extent
      place(wrapper.children[1],x,y,w,h,reset)
    end
  end
  segment(1,0,start,0)
  segment(3,start+thumb_length,travel-start,0)
  segment(5,start,thumb_length,1)
  return travel, start, thumb_length
end

local function render_viewport(c, st)
  local v = st.viewport
  local x, y = v.x, v.y
  local canvas = SK.scroll_pane(c).ssk_canvas
  canvas.style.left_margin, canvas.style.top_margin = -x, -y
  -- Slot button chrome can draw outside the pane. Bars and ribbons clip normally.
  for _, visual in pairs(v.has_nodes and st.node_visuals or {}) do
    local icon = visual.icon
    if icon then
      local bounds, guard = visual.icon_bounds, 8
      local inside = bounds[1] >= x + guard and bounds[2] >= y + guard
        and bounds[3] <= x + v.w - guard and bounds[4] <= y + v.h - guard
      if icon.visible ~= inside then
        icon.visible = inside
        icon.parent.ignored_by_interaction = not inside
      end
    end
  end
  local overview = c.ssk_body.ssk_sidebar.ssk_overview
  local outline = overview.ssk_overview_map.ssk_viewport_outline
  local scale, ox, oy = v.map_scale, v.map_x, v.map_y
  local left, top = round(ox + x / v.zoom * scale), round(oy + y / v.zoom * scale)
  local right = round(ox + math.min(v.content_w, (x + v.w) / v.zoom) * scale)
  local bottom = round(oy + math.min(v.content_h, (y + v.h) / v.zoom) * scale)
  local w, h = math.max(1, right - left), math.max(1, bottom - top)
  local t = math.min(2, w, h)
  local el = outline.children
  place(el[1].children[1], left, top, w, t, el[2])
  place(el[3].children[1], left, top + h - t, w, t, el[4])
  place(el[5].children[1], left, top, t, h, el[6])
  place(el[7].children[1], left + w - t, top, t, h, el[8])
  local chart = c.ssk_body.ssk_viewport
  v.travel_x, v.thumb_x, v.thumb_w = update_track(chart.ssk_scroll_x, "x", v.w, x, v.max_x)
  v.travel_y, v.thumb_y, v.thumb_h = update_track(chart.ssk_viewport_row.ssk_scroll_y, "y", v.h, y, v.max_y)
end

local function render_selection(parent, L, us, width, height, player, options, drawer_x)
  local key, sidx = us.sel, us.sidx or player.surface.index
  local selected = L.nodes[key]
  local material = key and material_key(selected or {key=key})
  if material then
    local kind, name = material:match("^(%a+)/(.+)$")
    if not prototypes[kind][name] then material = nil end
  end
  local summary = parent.ssk_selected_material
  local has_bars = next(L.nodes) ~= nil
  if summary and (summary.tags.key ~= key or summary.tags.width ~= width or not key and summary.tags.has_bars ~= has_bars) then
    summary.destroy()
    summary = nil
  end
  if not selected or us.selection_actions ~= key then us.selection_actions = nil end
  if drawer_x and not key then return end
  local text_width = width - 36
  if not summary then
    summary = parent.add{type="frame", name="ssk_selected_material", style="inside_deep_frame", direction="vertical",
      tags={key=key, width=width, has_bars=has_bars}}
    summary.style.width, summary.style.padding = width, 8
    summary.style.vertically_stretchable = key ~= nil and not drawer_x
    if key then
      local node = selected or {key=key}
      local title = Loc.join(rt(sprite_for(node)), " ", display_name(node))
      local header = summary.add{type="flow", direction="horizontal", style="frame_header_flow"}
      header.style.vertical_align = "center"
      local label = header.add{type="label", style="caption_label", caption=title, tooltip=title}
      label.style.maximal_width = text_width - 16
      header.add{type="empty-widget", ignored_by_interaction=true}.style.horizontally_stretchable = true
      header.add{type="sprite-button", style="frame_action_button", sprite="utility/close",
        tooltip=Loc("sankey-deselect"), tags={ssk_sk="deselect"}}
      local row = option_row(summary, "ssk_selection_actions")
      row.style.top_margin = 2
      if material then selection_links(row, material) end
      row.add{type="empty-widget", ignored_by_interaction=true}.style.horizontally_stretchable = true
      row.add{type="sprite-button", name="ssk_selection_more", style="tool_button", sprite="utility/expand_dots",
        tags={ssk_sk="selection_actions"}}
      local divider = summary.add{type="line", name="ssk_selection_header_divider"}
      divider.style.width, divider.style.top_margin, divider.style.bottom_margin = text_width, 2, 2
    else
      summary.add{type="label", name="ssk_selection_empty", style="caption_label", caption=Loc("sankey-selection-empty")}
      if has_bars then
        local prompt = summary.add{type="label", name="ssk_selection_prompt", style="grey_label", caption=Loc("sankey-overview-empty")}
        prompt.style.single_line, prompt.style.maximal_width = false, text_width
        prompt.style.top_margin = 2
      end
      return
    end
    local pane = summary.add{type="scroll-pane", name="ssk_selected_scroll", style="naked_scroll_pane",
      horizontal_scroll_policy="never", vertical_scroll_policy="auto-and-reserve-space"}
    pane.style.vertically_stretchable = true
    pane.add{type="flow", name="ssk_rate_card_body", direction="vertical"}.style.vertical_spacing = 6
  end
  if not key then return end
  if drawer_x then
    -- Cancel the drawer's height so opening a selection leaves the chart in place.
    local top, drawer_height = -height + 4, height - 8
    summary.style.height, summary.style.left_margin = drawer_height, drawer_x
    summary.style.top_margin, summary.style.bottom_margin = top, -(top + drawer_height)
    summary.visible = not us.settings_open
  end

  local more = summary.ssk_selection_actions.ssk_selection_more
  local menu_open = selected ~= nil and us.selection_actions == key
  local newly_opened = menu_open and not more.toggled
  more.enabled, more.toggled = selected ~= nil, menu_open
  more.tooltip = Loc(selected and "sankey-selection-actions" or "sankey-selection-actions-unavailable")
  local pane = summary.ssk_selected_scroll
  local menu = pane.ssk_selection_menu
  if menu and (not selected or menu.tags.group ~= selected.group or menu.tags.layout ~= us.layout) then
    menu.destroy()
    menu = nil
  end
  if menu_open and not menu then
    menu = pane.add{type="frame", name="ssk_selection_menu", index=1, style="inside_shallow_frame", direction="vertical",
      tags={group=selected.group, layout=us.layout}}
    menu.style.padding, menu.style.width = 8, text_width
    menu.style.bottom_margin = 4
    selection_controls(menu, selected, us, player, text_width - 16)
  end
  if menu then menu.visible = menu_open end

  local body = pane.ssk_rate_card_body
  body.tags = {tick=math.floor(game.tick / 300)}
  local function row(caption, style, index)
    local label = body.add{type="label", caption=caption, style=style, index=index}
    label.style.width, label.style.single_line = text_width, false
    return label
  end
  if material then
    RateCard.render_body(body, sidx, material, us.period or Sampler.DEFAULT_PERIOD, text_width, options)
    if selected then
      local masked = recipe_summary(selected, 3, options.recipe_icons, true)
      if #masked > 0 then
        body.add{type="line"}
        for _, line in ipairs(masked) do row(line, "grey_label") end
      end
    else
      row(Loc("sankey-selection-no-bar"), "grey_label", 2)
    end
  else
    body.clear()
    if not selected then
      row(Loc("sankey-selection-no-bar"), "grey_label")
    elseif selected.transport then
      row(transport_tooltip(selected.transport, false))
    elseif selected.kind == "recipe" then
      local rate = L.recipe_rates[selected.key:sub(8)]
      if rate then row(Loc.join(fmt(rate.cps or 0), " ", units(selected))) end
    else
      row(Loc.join(selected.ginfo.super_name, " › ", selected.ginfo.name), "grey_label")
      row(Loc("sankey-produced-consumed", fmt(selected.prod), units(selected), fmt(selected.cons), units(selected)))
      for _, line in ipairs(recipe_summary(selected, nil, options.recipe_icons)) do row(line) end
    end
  end
  if newly_opened then pane.scroll_to_element(menu, "in-view") end
end

-- st: runtime per-player render state (ribbon element refs for hover)
local function rstate(pi, view)
  storage.sk_render = storage.sk_render or {}
  local k = (view == "focus") and (Loc.join(pi, ":focus")) or pi
  storage.sk_render[k] = storage.sk_render[k] or { ribbons = {} }
  return storage.sk_render[k]
end

function SK.toolbar_height()
  return 2 * STRIP_PAD_Y + FIRST_ROW_H
end

-- c: tab content (vertical flow). full=false keeps the scroll-pane (and its scroll position).
function SK.scroll_pane(c)
  local body = c.ssk_body
  local chart = body and body.ssk_viewport
  return chart and chart.ssk_viewport_row.ssk_sp or body and body.ssk_sp or c.ssk_sp
end

function SK.pan_to(player, c, us, x, y)
  local st = rstate(player.index, us.view)
  local v = st.viewport
  if not (v and c and c.valid and c.ssk_body and c.ssk_body.ssk_sidebar) then return false end
  x, y = clamp_pan(x, v.max_x), clamp_pan(y, v.max_y)
  if x == v.x and y == v.y then return true end
  SK.clear_hover(player.index)
  v.x, v.y = x, y
  render_viewport(c, st)
  return true
end

function SK.fill(player, c, us, W, viewH, full, only_auto, source, refresh_graph)
  if only_auto and not full and us.oversized then return end
  local hovered=storage.sk_hover and storage.sk_hover[player.index]
  if hovered and hovered.valid then
    local ancestor=hovered
    while ancestor and ancestor~=c do ancestor=ancestor.parent end
    if ancestor==c and only_auto and not full then return end
  end
  SK.clear_hover(player.index)
  SK.defaults(us)
  local keep_controls = (only_auto or refresh_graph) and not full
  local full_chart = not source and us.view ~= "focus" and not us.neighborhood
  local ribbon_setting = player.mod_settings["ssk-detailed-sankey-ribbons"]
  local detailed_ribbons = not full_chart or (ribbon_setting ~= nil and ribbon_setting.value == true)
  us.detailed_ribbons = detailed_ribbons
  local scalable_chart = full_chart or (source and source.chart_zoom)
  local inspector_w = math.min(INSPECTOR_W, W - 16)
  local sidebar_w = full_chart and W >= SIDEBAR_MIN_W and INSPECTOR_W or 0
  local chart_w = W - (sidebar_w > 0 and sidebar_w + 8 or 0)
  local with_sidebar = sidebar_w > 0
  local band_setting = settings.global["ssk-sankey-overview-bands"]
  local overview_bands = with_sidebar and (not band_setting or band_setting.value)
  local drawer_x = full_chart and not with_sidebar and W - inspector_w - 4
  local setting = player.mod_settings["ssk-live-sankey-overview"]
  local managed_scroll = with_sidebar and setting ~= nil and setting.value == true
  local body = c.ssk_body
  if full or not SK.scroll_pane(c) or (body ~= nil) ~= with_sidebar
    or (body and (body.ssk_viewport ~= nil) ~= managed_scroll) then
    c.clear()
    c.add { type = "scroll-pane", name = "ssk_bar", style = "naked_scroll_pane", horizontal_scroll_policy = "auto", vertical_scroll_policy = "auto" }
    local body = c
    if with_sidebar then
      body = c.add{type="flow", name="ssk_body", direction="horizontal"}
      body.style.horizontal_spacing = 8
    end
    local chart, row = body, body
    if managed_scroll then
      chart = body.add{type="flow", name="ssk_viewport", direction="vertical"}
      chart.style.vertical_spacing = 0
      row = chart.add{type="flow", name="ssk_viewport_row", direction="horizontal"}
      row.style.horizontal_spacing = 0
    end
    local sp = row.add { type = "scroll-pane", name = "ssk_sp", style = "naked_scroll_pane",
                       horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
    sp.style.horizontally_stretchable = not full_chart
    sp.style.height = viewH
    local canvas = sp.add { type = "flow", name = "ssk_canvas", direction = "vertical" }
    canvas.style.vertical_spacing = 0
    if managed_scroll then
      scroll_track(row,"y")
      scroll_track(chart,"x")
    end
    if with_sidebar then body.add{type="flow", name="ssk_sidebar", direction="vertical"} end
  end
  c.ssk_bar.visible = not source
  c.ssk_bar.style.width = W
  us.toolbar_width = W
  local pane = SK.scroll_pane(c)
  pane.style.height = viewH
  pane.vertical_scroll_policy = managed_scroll and "never" or "auto-and-reserve-space"
  if full_chart then pane.style.width = chart_w end
  c.ssk_bar.style.height = SK.toolbar_height()
  c.ssk_bar.style.padding = 0
  local canvas = pane.ssk_canvas
  if us.view == "focus" and not us.focus then
    if not keep_controls or #c.ssk_bar.children==0 then
      focus_toolbar(c.ssk_bar, us, player)
      settings_panel(c, us, nil, W, viewH)
    end
    canvas.clear()
    Canvas.clear(player.index)
    local l = canvas.add { type = "label", caption = us.neighborhood and Loc("sankey-select-an-item-or-fluid-from-the") or Loc("sankey-pick-an-item-or-fluid-above-or") }
    l.style.single_line = false
    place(l, 24, 40, math.max(100, W - 48), 60)
    return
  end
  local L, model, unchanged = View.build(player, us, chart_w, viewH, source, only_auto and not full and #canvas.children > 0)
  local inspector = full_chart and (with_sidebar and c.ssk_body.ssk_sidebar or c)
  local function update_inspector(layout, read_balance, recipe_icons, fresh)
    local options = {model=model, read_balance=read_balance, recipe_rates=layout.details and layout.details.rates,
      recipe_icons=recipe_icons, plot_height=100, recipe_tables=true, player=player, fresh=fresh}
    render_selection(inspector, layout, us, inspector_w, viewH, player, options, drawer_x)
  end
  if not L then
    -- The history clock advances even when every rate and ribbon on the chart is unchanged.
    local summary = inspector and inspector.ssk_selected_material
    local scroll = summary and summary.ssk_selected_scroll
    local body = scroll and scroll.ssk_rate_card_body
    if unchanged and body and body.tags.tick ~= math.floor(game.tick / 300) then
      update_inspector(unchanged, nil, observed_recipe_icons(player, us), false)
    end
    return
  end
  local size_changed = us.oversized ~= (L.budget ~= nil)
  us.oversized, us.render_fingerprint = L.budget ~= nil, L.render_fingerprint
  local notice = c.ssk_size_notice
  if full_chart then
    if notice then notice.destroy() end
  else
    if not notice then
      notice = c.add { type = "label", name = "ssk_size_notice", index = 2 }
      notice.style.height = 24
      notice.style.left_padding = 8
    end
    update_size_notice(notice, L.budget)
    if L.budget then
      viewH = math.max(100, viewH - 24)
      pane.style.height = viewH
    end
  end
  local zoom = 1
  if scalable_chart then
    zoom = us.chart_zoom or 1
    if us.chart_fit then
      zoom = math.min(1, math.max(1, chart_w - 26) / math.max(1, L.content_w),
        math.max(1, viewH - 12) / math.max(1, L.content_h))
      local step = math.floor(zoom * 10) / 10
      if step > 0 then zoom = step end
    end
    us.render_zoom = zoom
  end
  local strip = c.ssk_bar.ssk_toolbar_strip
  local rows = strip and strip.ssk_toolbar_rows
  local toolbar = rows and rows.ssk_toolbar_main
  if not source and (not keep_controls or size_changed or not toolbar or full_chart and not toolbar.ssk_toolbar_middle) then
    toolbar = build_toolbar(c.ssk_bar, us, player)
    settings_panel(c, us, L, W, viewH)
  elseif source then
    if not keep_controls or size_changed or (us.settings_open and not c.ssk_settings) then
      settings_panel(c, us, L, W, viewH, source.mode ~= "capacity")
    end
  else
    local actions = toolbar and toolbar.ssk_toolbar_actions
    if actions and actions.ssk_zoom then
      actions.ssk_zoom.caption = Loc("sankey-chart-zoom", round((scalable_chart and zoom or (us.zoom or 1)) * 100))
    end
  end
  if full_chart then
    local middle = toolbar.ssk_toolbar_middle
    local status = middle.ssk_size_notice
    update_size_notice(status, L.budget)
    middle.tooltip = L.budget and Loc.join(status.caption, "\n", status.tooltip) or nil
  end
  us.last_order = L.order
  us.last_lanes = L.lane_order
  us.last_subs = L.sub_order

  canvas.clear()
  local width = math.ceil(L.content_w * zoom)
  local height = math.ceil(L.content_h * zoom)
  local inner_w = managed_scroll and chart_w - SCROLLBAR or scalable_chart and chart_w - 18 or chart_w
  local inner_h = managed_scroll and viewH - (width > inner_w and SCROLLBAR or 0) or viewH - 4
  local CW = math.max(inner_w, width)
  local CH = math.max(inner_h, height)
  canvas.style.width = CW
  canvas.style.height = CH
  pane.horizontal_scroll_policy = (not managed_scroll and CW > inner_w) and "auto" or "never"
  if managed_scroll then
    pane.style.width, pane.style.height = inner_w, inner_h
    c.ssk_body.ssk_viewport.ssk_scroll_x.visible = width > inner_w
  end
  local nn = 0
  for _ in pairs(L.nodes) do nn = nn + 1 end
  local recipe_icons = full_chart and nn > 0 and observed_recipe_icons(player, us)
  local paths = {}
  local chain
  local st = rstate(player.index, us.view)
  st.viewport = nil
  if full_chart and not managed_scroll then us.chart_viewport = nil end
  local read_balance
  if not source and model and model.used and model.rates and (nn > 0 or (full_chart and us.sel)) then
    read_balance = Balance.material_reader(us.sidx or player.surface.index, model, true)
  end
  if nn == 0 then
    Canvas.clear(player.index)
    local caption = (L.seconds < 2)
      and Loc("sankey-collecting-data-rates-appear-after-the-first")
      or Loc("sankey-nothing-to-show-for-this-preset-scope")
    if us.view == "focus" and L.seconds >= 2 then
      caption = Loc("no-recorded-material-flow", localised_name({key=us.focus}))
    end
    local l = canvas.add { type = "label", caption = source and source.empty or caption }
    l.style.single_line = false
    local empty_width = chart_w - 48
    if drawer_x and us.sel and not us.settings_open then
      empty_width = drawer_x - 32
      l.visible = empty_width >= 100
    end
    place(l, 24, 40, math.max(100, empty_width), 80)
  else
    local _, selection = draw(canvas, L, us, st, player, CW, CH, zoom, recipe_icons, read_balance, detailed_ribbons)
    chain = selection
    paths = st.paths
    if not managed_scroll and (us.center_pending or (us.neighborhood and (us.centered_focus ~= us.focus or full))) then
      local n=L.nodes[us.view=="focus" and us.focus or us.sel]
      do
        local aw, ah=math.min(chart_w-26,CW), math.min(viewH-24,CH)
        local mx=n and (n.x+View.NODE_W/2)*zoom or (us.fit_pending and aw/2 or width/2)
        local my=n and (n.y+n.h/2)*zoom or (us.fit_pending and ah/2 or height/2)
        local x=math.max(0,math.min(CW-aw,mx-aw/2))
        local y=math.max(0,math.min(CH-ah,my-ah/2))
        local anchor=canvas.add{type="empty-widget", ignored_by_interaction=true}
        place(anchor,x,y,aw,ah)
        pane.scroll_to_element(anchor)
      end
      us.center_pending,us.centered_focus=false,us.focus
      us.fit_pending=nil
    end
  end
  if with_sidebar then
    local side = c.ssk_body.ssk_sidebar
    side.style.width, side.style.height, side.style.vertical_spacing = sidebar_w, viewH, 8
    local map_scale, map_x, map_y = render_overview(side, L, us, paths, chain, sidebar_w, viewH, player,
      managed_scroll, overview_bands)
    if managed_scroll then
      local previous = us.chart_viewport
      local v = {w=inner_w, h=inner_h, zoom=zoom, max_x=CW-inner_w, max_y=CH-inner_h}
      local x, y = previous and previous.x or 0, previous and previous.y or 0
      if us.fit_pending or nn == 0 then
        x, y = 0, 0
      elseif us.center_pending and not us.zoom_pending then
        local n = L.nodes[us.sel]
        x = (n and (n.x + View.NODE_W / 2) * zoom or width / 2) - v.w / 2
        y = (n and (n.y + n.h / 2) * zoom or height / 2) - v.h / 2
      elseif previous and previous.zoom ~= zoom then
        x = (x + previous.w / 2) * zoom / previous.zoom - v.w / 2
        y = (y + previous.h / 2) * zoom / previous.zoom - v.h / 2
      end
      v.x, v.y = clamp_pan(x, v.max_x), clamp_pan(y, v.max_y)
      st.viewport, us.chart_viewport = v, v
      v.content_w, v.content_h, v.has_nodes = L.content_w, L.content_h, nn > 0
      v.map_scale, v.map_x, v.map_y = map_scale, map_x, map_y
      local overview = side.ssk_overview
      overview.ssk_overview_map.ssk_viewport_outline.visible = nn > 0
      render_viewport(c, st)
      us.center_pending, us.fit_pending = nil, nil
    end
  end
  if inspector then update_inspector(L, read_balance, recipe_icons, not only_auto) end
  us.zoom_pending = nil
end

---------------------------------------------------------------------------
-- interaction
---------------------------------------------------------------------------
-- ▲/▼ cascade: inside the node's (sub-lane, column) bucket; at the bucket edge the
-- sub-lane moves inside its lane; at the lane edge the whole lane moves.
local function reorder(list, i, dir, to_end)
  local j
  if to_end then j = (dir < 0) and 1 or #list else j = i + dir end
  if j < 1 or j > #list or j == i then return false end
  local v = table.remove(list, i)
  table.insert(list, j, v)
  return true
end

local function move(player, us, dir, to_end)
  local key = us.sel
  if not key then return end
  local bucket, idx
  for bid, list in pairs(us.last_order or {}) do
    for i, k in ipairs(list) do if k == key then bucket, idx = bid, i end end
  end
  if not bucket then return end
  local list = us.last_order[bucket]
  if reorder(list, idx, dir, to_end) then
    for i, k in ipairs(list) do us.pos[k] = i end
    return
  end
  -- sub-lane level
  us.gpos = us.gpos or {}
  us.lpos = us.lpos or {}
  local gid = string.match(bucket, "^(.-)@%d+$")
  for li, lane in ipairs(us.last_lanes or {}) do
    local subs = (us.last_subs or {})[lane] or {}
    for si, sid in ipairs(subs) do
      if sid == gid then
        if reorder(subs, si, dir, false) then
          for i, g in ipairs(subs) do us.gpos[g] = i end
        else
          local lanes = us.last_lanes
          if reorder(lanes, li, dir, false) then
            for i, l in ipairs(lanes) do us.lpos[l] = i end
          end
        end
        return
      end
    end
  end
end

-- returns: nil (not ours) | "redraw" | "rebuild"
function SK.select_focus(us, key)
  if not key or key == us.focus then return false end
  us.focus_hist = us.focus_hist or {}
  if us.focus then table.insert(us.focus_hist, us.focus) end
  trim_history(us.focus_hist)
  us.focus = key
  us.focus_forward = {}
  return true
end

function SK.step_history(us, steps)
  if not steps or steps == 0 then return false end
  us.focus_hist, us.focus_forward = us.focus_hist or {}, us.focus_forward or {}
  local from = steps < 0 and us.focus_hist or us.focus_forward
  local to = steps < 0 and us.focus_forward or us.focus_hist
  if math.abs(steps) > #from then return false end
  for _ = 1, math.abs(steps) do
    if us.focus then to[#to + 1] = us.focus end
    us.focus = table.remove(from)
  end
  return true
end

function SK.on_click(e, us)
  local tags = e.element.tags
  if tags and tags.ssk_ui=="transport_history" then return nil end
  local a = tags and tags.ssk_sk
  if not a then return nil end
  SK.defaults(us)
  local player = game.get_player(e.player_index)
  local pi = player.index
  if a == "node" and us.neighborhood and e.shift then
    us.pinned = us.pinned ~= tags.key and tags.key or nil
  elseif a == "unpin" then us.pinned=nil; if us.view~="focus" then us.sel=nil end
  elseif a == "center_selection" then us.center_pending=true
  elseif a == "overview_jump" then us.sel, us.center_pending = tags.key, true
  elseif a == "node" and us.view == "focus" then
    local k = base_key(tags.key)
    if string.sub(k, 1, 6) == "group/" or string.sub(k, 1, 7) == "recipe/" or k == us.focus then return "none" end
    SK.select_focus(us, k)
  elseif a == "f_clear_history" then
    us.focus, us.sel, us.pinned = nil, nil, nil
    us.focus_hist, us.focus_forward = {}, {}
  elseif a == "f_back" or a == "f_forward" or a == "f_trail" then
    if not SK.step_history(us, a == "f_back" and -1 or a == "f_forward" and 1 or tags.steps) then return "none" end
  elseif a == "node" then
    us.sel = (us.sel ~= tags.key) and tags.key or nil
  elseif a == "chart_settings" then
    us.selection_actions = nil
    us.settings_open = not us.settings_open or nil
  elseif a == "selection_actions" then
    us.settings_open = nil
    us.selection_actions = us.selection_actions ~= us.sel and us.sel or nil
  elseif a == "inputs_more" then us.input_depth = math.min(View.MAX_INPUT_DEPTH, (us.input_depth or 1) + 1)
  elseif a == "inputs_less" then us.input_depth = math.max(1, (us.input_depth or 1) - 1)
  elseif a == "deselect" then us.sel = nil
  elseif a == "zoom_in" or a == "zoom_out" then
    if us.view == "focus" or us.neighborhood then
      local step = a == "zoom_in" and ZOOM_STEP or 1 / ZOOM_STEP
      us.zoom = math.max(0.25, math.min(8, us.zoom * step))
    else
      local zoom = us.render_zoom or 1
      local tenth = round(zoom * 100) / 10
      local next_step = a == "zoom_in" and math.floor(tenth) + 1 or math.ceil(tenth) - 1
      us.chart_zoom = math.max(math.min(0.02, zoom), math.min(2.5, next_step / 10))
      us.chart_fit, us.center_pending, us.zoom_pending = false, true, true
    end
  elseif a == "zoom_fit" then
    if us.view == "focus" or us.neighborhood then
      us.zoom, us.layout_snapshot = 1, nil
    else
      us.chart_fit = true
    end
    us.center_pending, us.fit_pending = true, true
  elseif a == "reflow" then us.reflow = (us.reflow or 0) + 1; us.auto_rank = {}
  elseif a == "overview_reset" then us.overview_open = {}; us.sel = nil
  elseif a == "reset_layout" then
    us.pos, us.gpos, us.lpos, us.hidden, us.collapsed = {}, {}, {}, {}, {}
    us.layout_snapshot, us.auto_rank, us.overview_open = nil, {}, {}
  elseif a == "up" or a == "down" then move(player, us, a == "up" and -1 or 1, e.shift)
  elseif a == "hide" then
    if us.sel then us.hidden[base_key(us.sel)] = true; us.sel = nil end
  elseif a == "unhide_all" then us.hidden = {}
  elseif a == "collapse" then us.collapsed[tags.gid] = true; us.sel = Loc.join("group/", tags.gid)
  elseif a == "expand" then
    if us.view == "overview" and string.sub(tags.gid, 1, 1) == "@" then
      us.overview_open = us.overview_open or {}; us.overview_open[string.sub(tags.gid, 2)] = true
    else us.collapsed[tags.gid] = nil end
    us.sel = nil
  elseif a == "ungroup" then if us.sel then Gr.unassign(pi, base_key(us.sel)) end
  elseif a == "new_group" then
    local tf = e.element.parent.ssk_newgroup
    local name = tf and tf.text or ""
    if us.sel and name ~= "" then
      local cur = Gr.info(pi, Gr.of(pi, base_key(us.sel)))
      local id = Gr.create(pi, name, cur.super)
      Gr.assign(pi, base_key(us.sel), id)
    else
      player.print(Loc("sankey-type-a-group-name-first"))
      return "redraw"
    end
  else
    return nil
  end
  return "rebuild"
end

function SK.on_selection(e, us)
  local tags = e.element.tags
  local a = tags and tags.ssk_sk
  if not a then return nil end
  SK.defaults(us)
  local i = e.element.selected_index
  if a == "view" then
    us.view = i == 1 and "overview" or "detail"
    us.sel, us.tier_lo, us.tier_hi = nil, nil, nil
  elseif a == "f_history" then
    if not SK.step_history(us, tags.steps and tags.steps[i - 1]) then return "none" end
  elseif a == "layout" then us.layout = (i == 2) and "lanes" or "clean"
  elseif a == "f_steps" then us.focus_steps = i
  elseif a == "f_heights" then us.heights = (i == 2) and "sqrt" or "linear"
  elseif a == "balance_colors" then us.color_mode = i==2 and "source" or "destination"
  elseif a == "f_lines" then us.lines = (i == 2) and "metro" or "curves"
  elseif a == "preset" then us.preset = us.preset_ids and us.preset_ids[i] or "all"; us.tier_lo, us.tier_hi = nil, nil
  elseif a == "tier_mode" then
    us.tier_mode = (i == 2) and "depth" or "tech"
    us.tier_lo, us.tier_hi = nil, nil
  elseif a == "tier_lo" then
    local v = us.tier_vals or {}
    us.tier_lo = (i > 1) and v[i] or nil
  elseif a == "tier_hi" then
    local v = us.tier_vals or {}
    us.tier_hi = (i < #v) and v[i] or nil
  elseif a == "move_group" then
    local id = us.group_ids and us.group_ids[i]
    if id and us.sel then Gr.assign(e.player_index, base_key(us.sel), id) end
  else
    return nil
  end
  return "rebuild"
end

function SK.on_checked(e, us)
  local tags = e.element.tags
  if not tags then return nil end
  if tags.ssk_sk == "live" then
    us.live = e.element.state
    return "none"
  elseif tags.ssk_sk == "split_raw" then
    us.split_raw = e.element.state
    return "rebuild"
  elseif tags.ssk_sk == "show_labels" then
    us.show_labels = e.element.state
    return "rebuild"
  end
  return nil
end

-- focus item pickers
function SK.on_elem_changed(e, us)
  local tags = e.element.tags
  local a = tags and tags.ssk_sk
  if a ~= "f_item" and a ~= "f_fluid" then return nil end
  local v = e.element.elem_value
  if type(v) == "table" then v = v.name end
  if not v then return "none" end
  local k = Loc.join(((a == "f_item") and "item/" or "fluid/"), v)
  SK.select_focus(us, k)
  return "rebuild"
end

-- state for the focus tab (kept inside the player's UI state)
function SK.focus_state(us)
  local fx = us.fx
  if not fx then
    fx = { view = "focus", focus_steps = 2, heights = "sqrt", lines = "curves", renderer = us.renderer }
    us.fx = fx
  end
  fx.period, fx.sidx = us.period, us.sidx
  fx.canvas_w, fx.canvas_h = us.canvas_w, us.canvas_h
  if fx.show_labels == nil then fx.show_labels = true end
  MaterialPicker.sanitize_state(fx)
  return fx
end

function SK.balance_state(us)
  if not us.bal_fx then us.bal_fx = { view = "focus", neighborhood = true, focus_steps = 1,
    heights = "sqrt", lines = "curves", renderer = us.renderer, live = true } end
  local fx = us.bal_fx
  fx.period, fx.sidx = us.period, us.sidx
  if fx.show_labels == nil then fx.show_labels = true end
  MaterialPicker.sanitize_state(fx)
  return fx
end

function SK.clear_hover(index)
  if storage.sk_hover then storage.sk_hover[index]=nil end
end

function SK.on_hover(e, entering)
  local tags = e.element.valid and e.element.tags
  if not tags or (tags.ssk_sk ~= "node" and tags.ssk_sk ~= "ribbon") then return false end
  -- Hover events are player/tick events. The saved element reference must also
  -- survive a script reload, since it controls deterministic GUI rebuilds.
  storage.sk_hover=storage.sk_hover or {}
  if entering then storage.sk_hover[e.player_index]=e.element
  elseif storage.sk_hover[e.player_index]==e.element then SK.clear_hover(e.player_index) end
  if tags.ssk_sk == "ribbon" then return true end
  local st = rstate(e.player_index, tags.fx and "focus" or nil)
  local key = entering and tags.key or st.selected
  highlight(st, key)
  return true
end

return SK
