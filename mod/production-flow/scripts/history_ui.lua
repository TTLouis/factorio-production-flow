-- Balance's single-material time series. The cameras share one plot width and
-- clock; the surrounding controls and legends remain ordinary Factorio GUI.
local Canvas = require("scripts.canvas")
local Graph = require("scripts.graph")
local History = require("scripts.history")
local Geometry = require("scripts.ribbon_geometry")
local MaterialPicker = require("scripts.material_picker")
local Sampler = require("scripts.sampler")
local Tooltip = require("scripts.tooltip")

local H = {}
local MADE = { 112, 224, 164 }
local USED = { 255, 79, 89 }
local NET_POSITIVE = { 100, 245, 114 }
local USES = { { 202, 131, 84 }, { 191, 160, 90 }, { 157, 92, 89 }, { 99, 112, 130 } }
local MEASURED = { 181, 203, 222 }
local ESTIMATED = { 67, 106, 126 }
local GRID = { 0.25, 0.25, 0.26, 1 }
local BASELINE = { 0.56, 0.54, 0.52, 1 }
local TICK_TEXT = { 0.78, 0.75, 0.71, 1 }
local HOVER_BAND = { 0.15, 0.12, 0.06, 0.24 }
local PLOT_GAP = 64
local PLOT_LEFT, PLOT_RIGHT = 52, 24
local PLOT_TOP, PLOT_BOTTOM = 12, 21
local STOCK_MARKER_HALF = 3
local SCROLL_INSET, SCROLLBAR_WIDTH, BODY_MARGIN_Y = 8, 12, 4
local hover_views = {}
local LAB_NOTE = "Lab use is estimated from measured science-pack consumption after recipe use. It may include spoilage or other untracked consumption."

local function color(rgb)
  return { rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1 }
end

local function swatch(rgb)
  return string.format("[color=#%02x%02x%02x]■[/color]", rgb[1], rgb[2], rgb[3])
end

local function number(n)
  local a = math.abs(n)
  if a >= 1000000000 then return string.format("%.3gG", n / 1000000000) end
  if a >= 1000000 then return string.format("%.3gM", n / 1000000) end
  if a >= 1000 then return string.format("%.3gk", n / 1000) end
  if a > 0 and a < 0.001 then return string.format("%.1g", n) end
  return string.format("%.3g", n)
end

local function material(key)
  if not key then return "No material selected" end
  if key == History.LABS then return "Labs (estimated)" end
  local kind, name = key:match("^([^/]+)/(.+)$")
  local proto = kind and prototypes[kind] and prototypes[kind][name]
  return proto and { "", Graph.rt(key), " ", proto.localised_name } or name or key
end

local function usage_tooltip(header, totals, seconds, units, skip)
  local parts, keys = { header }, {}
  for key, amount in pairs(totals) do
    if amount > 0 and not (skip and skip[key]) then keys[#keys + 1] = key end
  end
  if #keys == 0 then return header end
  table.sort(keys, function(a, b)
    if a == History.OTHER then return false end
    if b == History.OTHER then return true end
    if totals[a] == totals[b] then return a < b end
    return totals[a] > totals[b]
  end)
  local show_labs = totals[History.LABS] and totals[History.LABS] > 0 and not (skip and skip[History.LABS])
  parts[#parts + 1] = show_labs and "\n\nEstimated usage breakdown" or "\n\nEstimated usage by product"
  for _, key in ipairs(keys) do
    parts[#parts + 1] = { "", "\n", key == History.OTHER and "Unattributed use" or material(key),
      string.format("  %.5g %s", totals[key] / seconds, units) }
  end
  if show_labs then parts[#parts + 1] = "\n\n" .. LAB_NOTE end
  return Tooltip.lines(parts)
end

local function label(parent, name, caption, style, width)
  local element = parent.add { type = "label", name = name, caption = caption, style = style }
  if width then
    element.style.width = width
    element.style.single_line = true
  end
  return element
end

local function small(parent, name, caption, width)
  local element = label(parent, name, caption, nil, width)
  element.style.font = "default-small"
  return element
end

local function row(parent, name)
  local element = parent.add { type = "flow", name = name, direction = "horizontal" }
  element.style.vertical_align = "center"
  element.style.horizontally_stretchable = true
  return element
end

local function spacer(parent, name)
  local element = parent.add { type = "empty-widget", name = name }
  element.style.horizontally_stretchable = true
  return element
end

local function build(panel, width, chart_width, toolbar_height, scroll_height)
  local toolbar = panel.add { type = "frame", name = "ssk_history_toolbar", style = "subheader_frame", direction = "vertical" }
  toolbar.style.width, toolbar.style.height = width, toolbar_height
  toolbar.style.left_padding, toolbar.style.right_padding = 12, 12
  toolbar.style.top_padding, toolbar.style.bottom_padding = 8, 8
  toolbar.style.horizontally_stretchable = true
  local controls = toolbar.add { type = "flow", name = "ssk_history_controls", direction = "vertical" }
  controls.style.horizontally_stretchable = true
  controls.style.vertical_spacing = 8
  local header = row(controls, "ssk_history_header")
  header.style.height = 40
  MaterialPicker.add_heading(header, width)
  spacer(header)
  header.add { type = "checkbox", name = "ssk_history_from_zero", state = false, caption = "Start from 0",
    tooltip = "Fix the bottom of the Made and Used rate chart at zero. Uncheck to fit the axis to the recorded rates.",
    tags = { ssk_ui = "history_zero" } }
  header.add { type = "checkbox", name = "ssk_history_usage", state = true, caption = "Usage breakdown",
    tooltip = "Show estimated uses alongside the total Used rate.", tags = { ssk_ui = "history_usage" } }

  local scroll = panel.add { type = "scroll-pane", name = "ssk_history_scroll", style = "naked_scroll_pane",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
  scroll.style.width = width - 2 * SCROLL_INSET
  scroll.style.height = scroll_height
  scroll.style.margin = SCROLL_INSET
  local body = scroll.add { type = "flow", name = "ssk_history_body", direction = "vertical",
    tags = { ssk_history_layout = "flush_header" } }
  body.style.width = chart_width
  -- Match the reserved scrollbar width on the left so plot gutters stay even.
  body.style.left_margin = SCROLLBAR_WIDTH
  body.style.top_margin, body.style.bottom_margin = BODY_MARGIN_Y, BODY_MARGIN_Y
  body.style.vertical_spacing = 4

  local rate = row(body, "ssk_history_rate_title")
  label(rate, nil, "Rate history", "caption_label")
  spacer(rate)
  small(rate, "ssk_history_rate_legend", "")
  body.add { type = "flow", name = "ssk_history_rate_plot", direction = "vertical" }
  local rate_state = small(body, "ssk_history_rate_state", "", chart_width)
  rate_state.style.single_line = false
  local readout = row(body, "ssk_history_readout")
  small(readout, "ssk_history_coverage", "")
  spacer(readout)
  small(readout, "ssk_history_summary", "").style.horizontal_align = "right"

  local uses = body.add { type = "flow", name = "ssk_history_uses", direction = "vertical" }
  uses.style.vertical_spacing = 2
  local heading = row(uses, "ssk_history_usage_heading")
  label(heading, "ssk_history_usage_title", "Where it goes", "caption_label")
  spacer(heading)
  small(heading, "ssk_history_usage_average", "Average used")
  local products = uses.add { type = "table", name = "ssk_history_products", column_count = 4 }
  products.style.horizontal_spacing = 8
  local cell_width = math.floor((chart_width - 24) / 4)
  local rate_width = math.min(52, math.floor(cell_width * 0.45))
  for i = 1, 4 do
    local product = row(products, "ssk_history_use_" .. i)
    label(product, "material_name", "", nil, cell_width - rate_width - 4)
    small(product, "rate", "", rate_width).style.horizontal_align = "right"
  end

  local net = body.add { type = "flow", name = "ssk_history_net_section", direction = "vertical" }
  net.style.horizontally_stretchable = true
  net.add { type = "line", direction = "horizontal" }
  local net_title = row(net, "ssk_history_net_title")
  label(net_title, nil, "Net rate", "caption_label")
  spacer(net_title)
  small(net_title, "ssk_history_net_legend", "")
  net.add { type = "flow", name = "ssk_history_net_plot", direction = "vertical" }

  body.add { type = "line", direction = "horizontal" }
  local stock = row(body, "ssk_history_stock_title")
  label(stock, nil, "Chest stock", "caption_label")
  spacer(stock)
  small(stock, "ssk_history_stock_legend", swatch(MEASURED) .. " Measured  " .. swatch(ESTIMATED) .. " Estimated")
  body.add { type = "flow", name = "ssk_history_stock_plot", direction = "vertical" }
  local stock_state = small(body, "ssk_history_stock_state", "", chart_width)
  stock_state.style.single_line = false
  local note = small(body, "ssk_history_stock_note", "", chart_width)
  note.style.single_line = false
  note.tooltip = "Estimates use the recorded Made minus Used rate and are adjusted to meet the next measured scan. Light blue bars show physical chest counts at scan completion."
end

local function averages(h)
  local made, used, by_product = 0, 0, {}
  local partial = false
  for _, p in ipairs(h.points) do
    partial = partial or p.partial == true
    if p.made ~= nil then
      made, used = made + p.made * p.seconds, used + p.used * p.seconds
      for key, value in pairs(p.uses) do
        by_product[key] = (by_product[key] or 0) + value * p.seconds
      end
    end
  end
  return made / h.seconds, used / h.seconds, by_product, partial
end

local function nice_step(maximum, intervals)
  if maximum <= 0 then return 1 end
  local rough = maximum / intervals
  local decade = 10 ^ math.floor(math.log(rough, 10))
  local part = rough / decade
  return decade * (part <= 1 and 1 or part <= 2 and 2 or part <= 5 and 5 or 10)
end

local function ago(seconds)
  if seconds == 0 then return "Now" end
  if seconds >= 3600 then return "-" .. number(seconds / 3600) .. "h" end
  if seconds >= 60 then return "-" .. number(seconds / 60) .. "m" end
  return "-" .. number(seconds) .. "s"
end

local function time_x(h, width, tick)
  return PLOT_LEFT + (width - PLOT_LEFT - PLOT_RIGHT) * (tick - h.start_tick) / (h.end_tick - h.start_tick)
end

-- Identical x positions in every viewport, including the period's unrecorded time.
local function axes(painter, h, width, height, top, minimum, maximum, step)
  local left, right = PLOT_LEFT, width - PLOT_RIGHT
  local plot_top, bottom = top + PLOT_TOP, top + height - PLOT_BOTTOM
  local function x(tick)
    return time_x(h, width, tick)
  end
  local function y(value)
    return bottom - (bottom - plot_top) * (value - minimum) / (maximum - minimum)
  end
  local intervals = width >= 520 and 5 or 2
  for i = 0, intervals do
    local ratio = i / intervals
    local tick = h.start_tick + (h.end_tick - h.start_tick) * ratio
    local pos = x(tick)
    painter.line(pos, plot_top, pos, bottom, GRID, 1)
    painter.text(pos, bottom + 11, ago((h.end_tick - tick) / 60), TICK_TEXT, "center")
  end
  local first, last = math.floor(minimum / step + 0.5), math.floor(maximum / step + 0.5)
  for i = first, last do
    local value = i * step
    local pos = y(value)
    painter.line(left, pos, right, pos, value == 0 and BASELINE or GRID, 1)
    painter.text(left - 5, pos, number(value), TICK_TEXT, "right", (i == first or i == last) and "heading-2" or nil)
  end
  return x, y, left, right, plot_top
end

local function elapsed(h, tick)
  local seconds = math.floor((h.end_tick - tick) / 60 + 0.5)
  if seconds == 0 then return "Now" end
  if seconds < 60 then return string.format("%ds ago", seconds) end
  if seconds < 3600 then return string.format("%dm %02ds ago", math.floor(seconds / 60), seconds % 60) end
  return string.format("%dh %02dm %02ds ago", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

local function rate_regions(h, width, units)
  local regions = {}
  for _, p in ipairs(h.rolling_points or h.points) do
    if p.made ~= nil and not p.partial then
      local left = Geometry.round(time_x(h, width, p.start_tick))
      local right = Geometry.round(time_x(h, width, p.end_tick))
      if right > left then
        local start_tick = p.average_start_tick or p.start_tick
        local tooltip = string.format("%s to %s\nMade  %.5g %s\nUsed  %.5g %s\nNet  %.5g %s",
          elapsed(h, start_tick), elapsed(h, p.end_tick), p.made, units, p.used, units, p.net, units)
        if p.average_start_tick then
          local duration = Sampler.duration((p.end_tick - start_tick) / 60)
          tooltip = "Rolling average over " .. duration .. "\n" .. tooltip
        end
        tooltip = usage_tooltip(tooltip, p.usage_detail or {}, 1, units)
        regions[#regions + 1] = { left = left, right = right, tooltip = tooltip }
      end
    end
  end
  return regions
end

-- Plot bucket averages at the midpoint and trailing averages at the end.
-- A shared easing curve keeps the Used outline on its product bands.
local function rate_paths(points, x)
  local paths, path, previous = {}, nil, nil
  local function add(tick, a, b, mix)
    path[#path + 1] = { x = x(tick), a = a, b = b, mix = mix }
  end
  local function sample_tick(point)
    return point.average_start_tick and point.end_tick or (point.start_tick + point.end_tick) / 2
  end
  for _, point in ipairs(points) do
    if point.made ~= nil and not point.partial then
      local at = sample_tick(point)
      if previous and previous.end_tick == point.start_tick then
        local from = sample_tick(previous)
        local steps = math.max(4, math.min(8, math.ceil((x(at) - x(from)) / 4)))
        for i = 1, steps - 1 do
          local t = i / steps
          add(from + (at - from) * t, previous, point, t * t * (3 - 2 * t))
        end
      else
        if previous and not previous.average_start_tick then add(previous.end_tick, previous, previous, 0) end
        path = {}
        paths[#paths + 1] = path
        add(point.start_tick, point, point, 0)
      end
      add(at, point, point, 0)
      previous = point
    end
  end
  if previous and not previous.average_start_tick then add(previous.end_tick, previous, previous, 0) end
  return paths
end

local function blend(a, b, fraction)
  return a + (b - a) * fraction
end

local function trace(painter, path, y, field, line_color, dashed, zero)
  local first = path[1]
  local start_x, previous_x = first.x, first.x
  local previous_y = y(first.a[field])
  local offset = 0
  local negative = zero and color(USED)
  local function line(x1, y1, x2, y2)
    if zero then
      if (y1 < zero and y2 > zero) or (y1 > zero and y2 < zero) then
        local crossing = x1 + (x2 - x1) * (zero - y1) / (y2 - y1)
        painter.line(x1, y1, crossing, zero, y1 < zero and line_color or negative, 2)
        painter.line(crossing, zero, x2, y2, y2 < zero and line_color or negative, 2)
      else
        local tint = (y1 < zero or y2 < zero) and line_color or (y1 > zero or y2 > zero) and negative or BASELINE
        painter.line(x1, y1, x2, y2, tint, 2)
      end
    else
      painter.line(x1, y1, x2, y2, line_color, 2, dashed, offset)
      if dashed then offset = (offset + math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)) % 8 end
    end
  end
  for i = 2, #path do
    local sample = path[i]
    local pos = y(blend(sample.a[field], sample.b[field], sample.mix))
    if pos ~= previous_y then
      if previous_x > start_x then line(start_x, previous_y, previous_x, previous_y) end
      line(previous_x, previous_y, sample.x, pos)
      start_x, previous_y = sample.x, pos
    end
    previous_x = sample.x
  end
  if previous_x > start_x then line(start_x, previous_y, previous_x, previous_y) end
end

local function rate_bounds(h, mode, intervals, from_zero)
  local net = mode == "net"
  local lowest, highest = math.huge, 0
  for _, p in ipairs(h.rolling_points or h.points) do
    if p.made ~= nil and not p.partial then
      if net then
        highest = math.max(highest, math.abs(p.net))
      else
        lowest, highest = math.min(lowest, p.made, p.used), math.max(highest, p.made, p.used)
        if mode == "breakdown" then
          local boundary = 0
          for _, key in ipairs(h.usage_keys) do
            boundary = boundary + (p.uses[key] or 0)
            if boundary > 0 then lowest = math.min(lowest, boundary) end
          end
        end
      end
    end
  end
  if net then
    local step = nice_step(highest, math.floor(intervals / 2))
    local bound = math.max(step, math.ceil(highest / step) * step)
    return -bound, bound, step
  end
  if lowest == math.huge then lowest = 0 end
  -- Give flat and tightly clustered rates a visible range as well.
  local margin = math.max((highest - lowest) * 0.05, highest * 0.02)
  local low, high = from_zero and 0 or math.max(0, lowest - margin), highest + margin
  local step = nice_step(high - low, intervals)
  low = math.floor(low / step) * step
  return low, math.max(low + step, math.ceil(high / step) * step), step
end

local function draw_rates(painter, h, width, height, mode, top, paths, from_zero)
  local net = mode == "net"
  local intervals = height < 100 and 2 or height < 140 and 3 or 4
  local min_value, max_value, step = rate_bounds(h, mode, intervals, from_zero)
  local x, y = axes(painter, h, width, height, top, min_value, max_value, step)

  paths = paths or rate_paths(h.rolling_points or h.points, x)
  if mode == "breakdown" then
    for _, path in ipairs(paths) do
      local base = {}
      for i, key in ipairs(h.usage_keys) do
        local vertices, visible = {}, false
        for j, sample in ipairs(path) do
          local lower = base[j] or 0
          local amount = blend(sample.a.uses[key] or 0, sample.b.uses[key] or 0, sample.mix)
          local upper = lower + amount
          vertices[#vertices + 1] = { sample.x, y(math.max(min_value, upper)) }
          vertices[#vertices + 1] = { sample.x, y(math.max(min_value, lower)) }
          visible = visible or (amount > 0 and upper > min_value)
          base[j] = upper
        end
        if visible then painter.polygon(vertices, color(USES[key == History.OTHER and 4 or i])) end
      end
    end
  end
  for _, path in ipairs(paths) do
    if net then
      trace(painter, path, y, "net", color(NET_POSITIVE), false, y(0))
    else
      trace(painter, path, y, "made", color(MADE), false)
      trace(painter, path, y, "used", color(USED), true)
    end
  end
  return paths
end

local function draw_stock(painter, h, width, height, top)
  local highest = 0
  local regions = {}
  for _, sample in ipairs(h.stock) do highest = math.max(highest, sample.count) end
  local step = nice_step(highest, height < 100 and 2 or height < 140 and 3 or 4)
  local max_value = math.max(step, math.ceil(highest / step) * step)
  local x, y, left, right, plot_top = axes(painter, h, width, height, top, 0, max_value, step)
  local bottom, last_label = y(0), left - 56
  local function edge(a, b)
    return Geometry.round(x((a.tick + b.tick) / 2))
  end
  for i, sample in ipairs(h.stock) do
    local center = x(sample.tick)
    local previous, following = h.stock[i - 1], h.stock[i + 1]
    local x1 = sample.joined and previous and edge(previous, sample)
      or math.max(left, Geometry.round(center - STOCK_MARKER_HALF))
    local x2 = following and following.joined and edge(sample, following)
      or math.min(right, Geometry.round(center + STOCK_MARKER_HALF))
    -- Very close scans can share a pixel on long windows. Keep measurements
    -- visible and use the same rounded edge for both bars in a joined pair.
    if x1 == x2 and sample.measured then
      x1 = math.min(x1, right - 1)
      x2 = x1 + 1
    end
    local y1 = math.min(bottom - 1, y(sample.count))
    painter.rect(x1, y1, x2 - x1, bottom - y1, color(sample.measured and MEASURED or ESTIMATED))
    if x2 > x1 then
      local source = sample.measured and "Measured stock" or sample.live and "Estimated stock since last scan" or "Estimated stock"
      regions[#regions + 1] = { left = x1, right = x2,
        tooltip = string.format("%s\n%s  %.0f items", elapsed(h, sample.tick), source, sample.count) }
    end
    if sample.measured and center - last_label >= 56 then
      local label_x = math.min(right - 12, math.max(left + 12, center))
      painter.text(label_x, math.max(plot_top - 4, y1 - 8), number(sample.count), TICK_TEXT, "center")
      last_label = center
    end
  end
  return regions
end

-- Native tooltip targets line up with the plotted buckets. Lay the transparent
-- row over the camera using negative margins and keep its elements on refresh.
local function plot_tooltips(parent, height, regions)
  local hover_height = height - PLOT_TOP - PLOT_BOTTOM
  local layer = parent.ssk_history_tooltips
  if not layer then
    parent.style.vertical_spacing = 0
    layer = parent.add { type = "flow", name = "ssk_history_tooltips", direction = "horizontal" }
    layer.style.horizontal_spacing = 0
    layer.style.bottom_margin = PLOT_BOTTOM
  end
  layer.style.height = hover_height
  layer.style.top_margin = PLOT_TOP - height
  local children, last, index = layer.children, 0, 0
  for _, region in ipairs(regions) do
    local left = math.max(last, region.left)
    if region.right > left then
      index = index + 1
      local target = children[index] or layer.add { type = "empty-widget" }
      target.style.width, target.style.height = region.right - left, hover_height
      target.style.left_margin = left - last
      target.tags = { ssk_history_bucket = true, left = left, right = region.right }
      target.raise_hover_events = true
      target.tooltip, target.visible = region.tooltip, true
      last = region.right
    end
  end
  for i = index + 1, #children do children[i].visible = false end
end

local function camera(player, parent, name, painter, width, height, top, regions, bands)
  local view = parent[name]
  parent.visible = not not painter
  if not painter then return end
  local spec = Canvas.camera_spec(player, painter, top, height)
  if not view then
    spec.name, spec.ignored_by_interaction = name, true
    view = parent.add(spec)
    view.style.width = width
  else
    view.position = spec.position
  end
  view.style.height = height
  plot_tooltips(parent, height, regions)
  local y, h = top + PLOT_TOP, height - PLOT_TOP - PLOT_BOTTOM
  local band = painter.rect(PLOT_LEFT, y, 1, h, HOVER_BAND)
  band.visible = false
  bands[#bands + 1] = { rect = band, top = y, height = h }
end

local function highlight(view, target)
  view.target = target
  local region = target and target.tags
  for _, band in ipairs(view.bands) do
    local rect = band.rect
    if rect.valid then
      if region then
        view.painter.rect(region.left, band.top, region.right - region.left, band.height, HOVER_BAND, rect)
      end
      rect.visible = region ~= nil
    end
  end
end

function H.on_hover(e, entering)
  local target = e.element
  if not (target.valid and target.tags.ssk_history_bucket) then return false end
  local view = hover_views[e.player_index]
  if view then
    if entering then highlight(view, target)
    elseif target == view.target then highlight(view) end
  end
  return true
end

function H.clear_hover(index)
  local view = hover_views[index]
  if view then highlight(view); hover_views[index] = nil end
end

function H.fill(player, panel, us, key, width, panel_height, toolbar_height)
  local chart_width = width - 2 * (SCROLL_INSET + SCROLLBAR_WIDTH)
  local scroll_height = math.max(1, panel_height - toolbar_height - 2 * SCROLL_INSET)
  local scroll = panel.ssk_history_scroll
  local body = scroll and scroll.ssk_history_body
  if not body or body.tags.ssk_history_layout ~= "flush_header" then
    panel.clear()
    build(panel, width, chart_width, toolbar_height, scroll_height)
    body = panel.ssk_history_scroll.ssk_history_body
  end
  local controls = panel.ssk_history_toolbar.ssk_history_controls
  local header = controls.ssk_history_header
  local breakdown = us.bal_usage_breakdown ~= false
  local from_zero = us.bal_history_from_zero == true
  header.ssk_history_usage.state = breakdown
  header.ssk_history_from_zero.state = from_zero
  MaterialPicker.update_heading(header.ssk_material_heading, key)
  local readout = body.ssk_history_readout
  local summary = readout.ssk_history_summary
  local h = key and History.build(us.sidx, us.period, key)
  local rates = h and h.seconds > 0
  local made, used, uses, partial
  if rates then made, used, uses, partial = averages(h) end
  local active = rates and (made > 0 or used > 0)
  local stock = h and #h.stock > 0
  summary.caption = rates and string.format("Made %s/s   Used %s/s   Net %s%s/s",
    number(made), number(used), made > used and "+" or "", number(made - used)) or ""
  summary.visible = rates == true
  local legend = body.ssk_history_rate_title.ssk_history_rate_legend
  local units = key and key:sub(1, 6) == "fluid/" and "fluid/s" or "items/s"
  local period_tip = usage_tooltip("Average over recorded time in the selected period.",
    rates and (h.usage_totals or {}) or {}, rates and h.seconds or 1, units)
  summary.tooltip = period_tip
  local rolling = h and h.rolling_seconds
  local rate_prefix = rolling and "Rolling avg   " or ""
  local rolling_tip = rolling and ("Trailing average over up to " .. Sampler.duration(rolling)
    .. ". The window starts again after a gap. Hover a point to see the recorded time it uses.")
  legend.caption = rate_prefix .. swatch(MADE) .. " Made   " .. swatch(USED) .. " Used   " .. units
  legend.tooltip = rolling_tip or "Rates per recorded chart bucket."
  local rate_state = body.ssk_history_rate_state
  rate_state.visible = not active
  rate_state.caption = not key and "Select a material above or from the Balance list."
    or not rates and "Collecting production history. Rates appear once sampling has recorded this surface."
    or "No recorded production or consumption for this material in the selected period."
  local coverage = readout.ssk_history_coverage
  local duration = h and (h.end_tick - h.start_tick) / 60
  local missing = rates and duration - h.seconds or 0
  coverage.visible = missing >= 1 or partial == true
  if coverage.visible then
    coverage.caption = missing >= 1 and ("Recorded " .. Sampler.duration(h.seconds) .. " of " .. Sampler.duration(duration) .. ".")
      or "Some buckets have missing samples."
    coverage.tooltip = "The chart leaves gaps where a time bucket has missing samples. Period averages still use the recorded portions."
  end
  readout.visible = summary.visible or coverage.visible

  local usage = body.ssk_history_uses
  usage.visible = active and breakdown and #h.usage_keys > 0 or false
  if usage.visible then
    usage.ssk_history_usage_heading.ssk_history_usage_title.tooltip = period_tip
    usage.ssk_history_usage_heading.ssk_history_usage_average.tooltip = period_tip
    local named = {}
    for _, product in ipairs(h.usage_keys) do if product ~= History.OTHER then named[product] = true end end
    local other_tip = usage_tooltip("Usage outside the three products shown on the chart.", h.usage_totals or {},
      h.seconds, units, named)
    for i = 1, 4 do
      local entry = usage.ssk_history_products["ssk_history_use_" .. i]
      local product = h.usage_keys[i]
      entry.visible = product ~= nil
      if product then
        local other = product == History.OTHER
        local caption = other and "Other uses" or material(product)
        entry.material_name.caption = { "", swatch(USES[other and 4 or i]), " ", caption }
        entry.rate.caption = number((uses[product] or 0) / h.seconds) .. "/s"
        local tip = other and other_tip or { "", caption, string.format("\nEstimated usage  %.5g %s",
          (uses[product] or 0) / h.seconds, units) }
        if product == History.LABS then tip[#tip + 1] = "\n" .. LAB_NOTE end
        entry.material_name.tooltip, entry.rate.tooltip = tip, tip
      end
    end
  end

  local stock_state = body.ssk_history_stock_state
  stock_state.visible = not stock
  stock_state.caption = not key and "Select an item to view chest stock history."
    or h and not h.stock_supported and "Chest stock history is available for items. Fluid tanks are outside chest scans."
    or "No completed chest stock scan in the selected period."
  body.ssk_history_stock_title.ssk_history_stock_legend.visible = stock == true
  local stock_note = body.ssk_history_stock_note
  stock_note.visible = stock == true
  if stock then
    local last = h.stock[#h.stock]
    if last.live then
      stock_note.caption = string.format("Latest estimate: %s items (%s). Updated from recorded rates.",
        number(last.count), elapsed(h, last.tick))
    elseif #h.stock == 1 then
      stock_note.caption = "Stock estimates appear as rates are recorded after a scan."
    else
      stock_note.caption = "Dark blue bars estimate stock from recorded rates."
    end
  end

  local net = body.ssk_history_net_section
  net.visible = rates == true
  local net_legend = net.ssk_history_net_title.ssk_history_net_legend
  net_legend.caption = rate_prefix .. swatch(NET_POSITIVE) .. " Surplus   " .. swatch(USED) .. " Deficit   " .. units
  net_legend.tooltip = (rolling_tip and rolling_tip .. "\n" or "")
    .. "Made minus Used per second. Green shows a surplus. Red shows a deficit. Zero means production matches consumption."
  -- Allow a third of the inspector for the stock and net sections together,
  -- including their headings, note, and divider.
  local stock_heading_height, net_heading_height = 48, 36
  local compact_plot_height = math.max(136, math.floor(us.bal_height / 3) - stock_heading_height - net_heading_height)
  local stock_share = math.floor(compact_plot_height / 2)
  local stock_height = stock and stock_share or 0
  local net_height = rates and compact_plot_height - stock_share or 0
  -- Keep space for the fixed captions, dividers, and insets. Only budget
  -- space for the coverage and usage rows when they are shown.
  local chart_space = scroll_height - 132
  if readout.visible then chart_space = chart_space - 24 end
  if usage.visible then chart_space = chart_space - 46 end
  local rate_height = 0
  if active then
    rate_height = math.max(72, chart_space - net_height - stock_height)
  elseif rates then
    net_height = math.max(net_height, chart_space - 24 - stock_height)
  elseif stock then
    -- The rate status replaces its chart and the Net section is hidden.
    stock_height = math.max(stock_height, chart_space - 24 + net_heading_height)
  end
  local net_top = rate_height + PLOT_GAP
  local stock_top = net_top + net_height + PLOT_GAP
  local painter, stock_regions
  if rates or stock then
    painter = Canvas.begin(player, chart_width, stock and stock_top + stock_height or net_top + net_height)
    local paths
    if active then
      paths = draw_rates(painter, h, chart_width, rate_height, breakdown and "breakdown" or "total", 0, nil, from_zero)
    end
    if rates then draw_rates(painter, h, chart_width, net_height, "net", net_top, paths) end
    if stock then stock_regions = draw_stock(painter, h, chart_width, stock_height, stock_top) end
  else
    Canvas.clear(player.index)
  end
  local buckets = rates and rate_regions(h, chart_width, units)
  local bands = {}
  camera(player, body.ssk_history_rate_plot, "ssk_history_camera", active and painter, chart_width, rate_height, 0, buckets, bands)
  camera(player, net.ssk_history_net_plot, "ssk_history_net_camera", rates and painter, chart_width, net_height, net_top, buckets, bands)
  camera(player, body.ssk_history_stock_plot, "ssk_history_stock_camera", stock and painter, chart_width, stock_height, stock_top, stock_regions, bands)
  local previous = hover_views[player.index]
  local target = previous and previous.target
  local view = painter and { painter = painter, bands = bands, key = key, period = us.period, surface = us.sidx }
  hover_views[player.index] = view
  if view and target and target.valid and target.visible and target.parent.parent.visible
    and previous.key == key and previous.period == us.period and previous.surface == us.sidx then
    highlight(view, target)
  end
end

return H
