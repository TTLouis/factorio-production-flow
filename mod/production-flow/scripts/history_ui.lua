-- Balance's single-material time series. The cameras share one plot width and
-- clock; the surrounding controls and legends remain ordinary Factorio GUI.
local Canvas = require("scripts.canvas")
local Graph = require("scripts.graph")
local History = require("scripts.history")

local H = {}
local VIEWS = {
  { "all", "All", "Compare measured Made and Used, with estimated uses by product." },
  { "made", "Made", "Show the measured production rate." },
  { "used", "Used", "Show the measured consumption rate and estimated uses by product." },
  { "net", "Net", "Show the measured Made rate minus the Used rate." },
}
local MADE = { 112, 224, 164 }
local USED = { 255, 166, 110 }
local NET = { 131, 200, 242 }
local USES = { { 202, 131, 84 }, { 191, 160, 90 }, { 157, 92, 89 }, { 99, 112, 130 } }
local MEASURED = { 181, 203, 222 }
local ESTIMATED = { 67, 106, 126 }
local STRIPE = { 111, 155, 175 }
local GRID = { 0.25, 0.25, 0.26, 1 }
local BASELINE = { 0.56, 0.54, 0.52, 1 }
local TICK_TEXT = { 0.78, 0.75, 0.71, 1 }
local PLOT_GAP = 64
local PLOT_LEFT, PLOT_RIGHT = 52, 24
local STOCK_SLOTS = 12

local function color(rgb)
  return { rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1 }
end

local function mark(rgb, glyph)
  return string.format("[color=#%02x%02x%02x]%s[/color]", rgb[1], rgb[2], rgb[3], glyph)
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
  local kind, name = key:match("^([^/]+)/(.+)$")
  local proto = kind and prototypes[kind] and prototypes[kind][name]
  return proto and { "", Graph.rt(key), " ", proto.localised_name } or name or key
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

function H.add_header(header, width)
  label(header, "ssk_history_material", "", "caption_label", math.max(80, math.min(240, width - 156)))
  spacer(header, "ssk_history_spacer")
  if width >= 620 then
    small(header, "ssk_history_summary", "", width - 410).style.horizontal_align = "right"
  end
end

function H.show_header(header, visible)
  header.ssk_history_material.visible = visible
  header.ssk_history_spacer.visible = visible
  if header.ssk_history_summary then header.ssk_history_summary.visible = visible end
end

local function build(panel, width, height, chart_width)
  panel.style.width = width
  local controls = panel.add { type = "frame", name = "ssk_history_controls", style = "subheader_frame", direction = "vertical" }
  controls.style.left_padding, controls.style.right_padding = 8, 8
  controls.style.top_padding, controls.style.bottom_padding = 0, 4
  controls.style.horizontally_stretchable = true
  if width < 620 then small(controls, "ssk_history_summary", "", chart_width) end
  local filters = row(controls, "ssk_history_views")
  filters.style.height = 28
  label(filters, nil, "View", "caption_label")
  for _, view in ipairs(VIEWS) do
    filters.add { type = "radiobutton", name = "ssk_history_" .. view[1], state = view[1] == "all",
      caption = view[2], tooltip = view[3], tags = { ssk_ui = "history_view", view = view[1] } }
  end

  local scroll = panel.add { type = "scroll-pane", name = "ssk_history_scroll", style = "naked_scroll_pane",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
  scroll.style.width = width - 4
  scroll.style.height = math.max(72, height - (width < 620 and 56 or 40))
  local body = scroll.add { type = "flow", name = "ssk_history_body", direction = "vertical" }
  body.style.width = chart_width
  body.style.left_margin, body.style.top_margin = 8, 4
  body.style.vertical_spacing = 4

  local rate = row(body, "ssk_history_rate_title")
  label(rate, nil, "Rate history", "caption_label")
  spacer(rate)
  small(rate, "ssk_history_rate_legend", "")
  body.add { type = "flow", name = "ssk_history_rate_plot", direction = "vertical" }
  local rate_state = small(body, "ssk_history_rate_state", "", chart_width)
  rate_state.style.single_line = false
  small(body, "ssk_history_coverage", "", chart_width)

  local uses = body.add { type = "flow", name = "ssk_history_uses", direction = "vertical" }
  uses.style.vertical_spacing = 2
  local heading = row(uses)
  label(heading, nil, "Where it goes", "caption_label")
  spacer(heading)
  local average = small(heading, nil, "Average used")
  average.tooltip = "Estimated consumption of the selected material per second, averaged over recorded time in this period."
  local products = uses.add { type = "table", name = "ssk_history_products", column_count = 2 }
  products.style.horizontal_spacing = 8
  products.style.vertical_spacing = 2
  local cell_width = math.floor((chart_width - 8) / 2)
  for i = 1, 4 do
    local product = row(products, "ssk_history_use_" .. i)
    label(product, "material_name", "", nil, cell_width - 65)
    small(product, "rate", "", 61).style.horizontal_align = "right"
  end

  body.add { type = "line", direction = "horizontal" }
  local stock = row(body, "ssk_history_stock_title")
  label(stock, nil, "Chest stock", "caption_label")
  spacer(stock)
  small(stock, "ssk_history_stock_legend", mark(MEASURED, "||") .. " Measured  " .. mark(STRIPE, "//") .. " Estimated")
  body.add { type = "flow", name = "ssk_history_stock_plot", direction = "vertical" }
  local stock_state = small(body, "ssk_history_stock_state", "", chart_width)
  stock_state.style.single_line = false
  local note = small(body, "ssk_history_stock_note", "Striped bars estimate stock between completed scans.", chart_width)
  note.style.single_line = false
  note.tooltip = "Estimates use the recorded Made minus Used rate and are adjusted to meet the next measured scan. Solid bars show physical chest counts at scan completion."
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

-- Identical x positions in both viewports, including the period's unrecorded time.
local function axes(painter, h, width, height, top, minimum, maximum, step)
  local left, right = PLOT_LEFT, width - PLOT_RIGHT
  local plot_top, bottom = top + 12, top + height - 21
  local function x(tick)
    return left + (right - left) * (tick - h.start_tick) / (h.end_tick - h.start_tick)
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
  for i = math.ceil(minimum / step), math.floor(maximum / step + 1e-8) do
    local value = i * step
    local pos = y(value)
    painter.line(left, pos, right, pos, value == 0 and BASELINE or GRID, 1)
    painter.text(left - 5, pos, number(value), TICK_TEXT, "right")
  end
  return x, y, left, right, plot_top
end

local function draw_rates(painter, h, width, height, view)
  local show_made = view == "all" or view == "made"
  local show_used = view == "all" or view == "used"
  local highest = 0
  for _, p in ipairs(h.points) do
    if p.made ~= nil and not p.partial then
      if show_made then highest = math.max(highest, p.made) end
      if show_used then highest = math.max(highest, p.used) end
      if view == "net" then highest = math.max(highest, math.abs(p.net)) end
    end
  end
  local intervals = height < 100 and 2 or height < 140 and 3 or 4
  local step = nice_step(highest, view == "net" and math.floor(intervals / 2) or intervals)
  local max_value = math.max(step, math.ceil(highest / step) * step)
  local min_value = view == "net" and -max_value or 0
  local x, y = axes(painter, h, width, height, 0, min_value, max_value, step)

  if show_used then
    -- Independent quads in a triangle strip. Degenerate vertices keep adjacent
    -- buckets separate even if there is unrecorded time between them.
    local layers = {}
    for i in ipairs(h.usage_keys) do layers[i] = {} end
    for _, p in ipairs(h.points) do
      if p.used and p.used > 0 and not p.partial then
        local start, finish = x(p.start_tick), x(p.end_tick)
        local base = 0
        for i, key in ipairs(h.usage_keys) do
          local used = p.uses[key] or 0
          if used > 0 then
            local upper, lower = y(base + used), y(base)
            local points = layers[i]
            if #points > 0 then
              points[#points + 1] = points[#points]
              points[#points + 1] = { start, upper }
            end
            points[#points + 1] = { start, upper }
            points[#points + 1] = { start, lower }
            points[#points + 1] = { finish, upper }
            points[#points + 1] = { finish, lower }
            base = base + used
          end
        end
      end
    end
    for i, key in ipairs(h.usage_keys) do
      painter.polygon(layers[i], color(USES[key == History.OTHER and 4 or i]))
    end
  end
  local function trace(field, rgb, dashed)
    local previous, offset = nil, 0
    local line_color = color(rgb)
    for _, p in ipairs(h.points) do
      if p[field] ~= nil and not p.partial then
        local start, finish, value = x(p.start_tick), x(p.end_tick), y(p[field])
        if previous and previous.end_tick == p.start_tick then
          local last = y(previous[field])
          if last ~= value then
            painter.line(start, last, start, value, line_color, 2, dashed, offset)
            offset = (offset + math.abs(last - value)) % 8
          end
        else
          offset = 0
        end
        painter.line(start, value, finish, value, line_color, 2, dashed, offset)
        offset = (offset + finish - start) % 8
        previous = p
      end
    end
  end
  if show_made then trace("made", MADE, false) end
  if show_used then trace("used", USED, true) end
  if view == "net" then trace("net", NET, false) end
end

-- Keep every completed scan and at most one estimate per visual slot. Bars
-- retain their exact scan or estimate times on the rate chart's time axis.
local function stock_bars(h, clearance)
  local samples, occupied, measurements = {}, {}, {}
  local stride = (h.end_tick - h.start_tick) / STOCK_SLOTS
  local function slot(sample) return math.floor((sample.tick - h.start_tick) / stride) end
  local function near_scan(tick)
    for _, measured_tick in ipairs(measurements) do
      if math.abs(tick - measured_tick) < clearance then return true end
    end
    return false
  end
  for _, sample in ipairs(h.stock) do
    if sample.measured then
      occupied[slot(sample)] = true
      measurements[#measurements + 1] = sample.tick
    end
  end
  for _, sample in ipairs(h.stock) do
    local position = slot(sample)
    if sample.measured or (not occupied[position] and not near_scan(sample.tick)) then
      samples[#samples + 1] = sample
      occupied[position] = true
    end
  end
  return samples
end

local function draw_stock(painter, h, width, height, top)
  local plot_width = width - PLOT_LEFT - PLOT_RIGHT
  local bar_width = math.min(42, plot_width / STOCK_SLOTS * 0.72)
  local clearance = (bar_width + 4) / plot_width * (h.end_tick - h.start_tick)
  local samples = stock_bars(h, clearance)
  local highest = 0
  for _, sample in ipairs(samples) do highest = math.max(highest, sample.count) end
  local step = nice_step(highest, height < 100 and 2 or height < 140 and 3 or 4)
  local max_value = math.max(step, math.ceil(highest / step) * step)
  local x, y, left, right, plot_top = axes(painter, h, width, height, top, 0, max_value, step)
  local bottom, last_label = y(0), left - 56
  for index, sample in ipairs(samples) do
    local center = x(sample.tick)
    local previous, next_sample = samples[index - 1], samples[index + 1]
    local spacing = math.min(previous and center - x(previous.tick) or math.huge,
      next_sample and x(next_sample.tick) - center or math.huge)
    -- Leave a gap between neighboring scans, even when the visible period
    -- greatly exceeds the retained scan history. Keep an edge bar one pixel wide.
    local half = math.max(0.5, math.min(bar_width, spacing * 0.8, spacing - 2) / 2)
    local x1 = math.max(left, math.min(right - 1, center - half))
    local x2 = math.min(right, math.max(x1 + 1, center + half))
    local y1 = math.min(bottom - 2, y(sample.count))
    painter.rect(x1, y1, x2 - x1, bottom - y1, color(sample.measured and MEASURED or ESTIMATED))
    if not sample.measured then
      for i = 1, 3 do
        local stripe = y1 + (bottom - y1) * i / 4
        local rise = math.min(4, (bottom - y1) / 4)
        painter.line(x1, stripe + rise, x2, stripe, color(STRIPE), 1)
      end
    elseif center - last_label >= 56 then
      painter.text(center, math.max(plot_top - 4, y1 - 8), number(sample.count), TICK_TEXT, "center")
      last_label = center
    end
  end
end

local function camera(player, parent, name, painter, width, height, top)
  local view = parent[name]
  parent.visible = not not painter
  if not painter then return end
  local spec = Canvas.camera_spec(player, painter, top, height)
  if not view then
    spec.name, spec.ignored_by_interaction = name, true
    view = parent.add(spec)
    view.style.width, view.style.height = width, height
  else
    view.position = spec.position
  end
end

function H.fill(player, panel, header, us, key, width, height)
  local chart_width = width - 30
  if not panel.ssk_history_scroll then build(panel, width, height, chart_width) end
  local controls = panel.ssk_history_controls
  local body = panel.ssk_history_scroll.ssk_history_body
  local view = us.bal_history_view or "all"
  for _, spec in ipairs(VIEWS) do
    controls.ssk_history_views["ssk_history_" .. spec[1]].state = spec[1] == view
  end
  local name = material(key)
  header.ssk_history_material.caption = name
  header.ssk_history_material.tooltip = name
  local summary = header.ssk_history_summary or controls.ssk_history_summary
  local h = key and History.build(us.sidx, us.period, key)
  local rates = h and h.seconds > 0
  local made, used, uses, partial
  if rates then made, used, uses, partial = averages(h) end
  local active = rates and (made > 0 or used > 0)
  local stock = h and #h.stock > 0
  summary.caption = rates and string.format("Made %s/s   Used %s/s   Net %s%s/s",
    number(made), number(used), made > used and "+" or "", number(made - used)) or ""
  summary.visible = rates == true
  summary.tooltip = "Measured average per second over the recorded time in the selected period."
  local legend = body.ssk_history_rate_title.ssk_history_rate_legend
  local units = key and key:sub(1, 6) == "fluid/" and "fluid/s" or "items/s"
  local made_legend, used_legend, net_legend = mark(MADE, "==") .. " Made",
    mark(USED, "--") .. " Used", mark(NET, "==") .. " Net"
  legend.caption = (view == "all" and made_legend .. "   " .. used_legend or view == "made" and made_legend
    or view == "used" and used_legend or net_legend) .. "   " .. units
  local rate_state = body.ssk_history_rate_state
  rate_state.visible = not active
  rate_state.caption = not key and "Select a material from the Balance table."
    or not rates and "Collecting production history. Rates appear once sampling has recorded this surface."
    or "No recorded production or consumption for this material in the selected period."
  local coverage = body.ssk_history_coverage
  local duration = h and (h.end_tick - h.start_tick) / 60
  local missing = rates and duration - h.seconds or 0
  coverage.visible = missing >= 1 or partial == true
  if coverage.visible then
    coverage.caption = missing >= 1 and string.format("Recorded %.0f of %.0f s.", h.seconds, duration)
      or "Some buckets have missing samples."
    coverage.tooltip = "The chart leaves gaps where a time bucket has missing samples. Period averages still use the recorded portions."
  end

  local usage = body.ssk_history_uses
  usage.visible = active and #h.usage_keys > 0 and (view == "all" or view == "used") or false
  if usage.visible then
    for i = 1, 4 do
      local entry = usage.ssk_history_products["ssk_history_use_" .. i]
      local product = h.usage_keys[i]
      entry.visible = product ~= nil
      if product then
        local other = product == History.OTHER
        local caption = other and "Other uses" or material(product)
        entry.material_name.caption = { "", mark(USES[other and 4 or i], "||"), " ", caption }
        entry.material_name.tooltip = caption
        entry.rate.caption = number((uses[product] or 0) / h.seconds) .. "/s"
        entry.rate.tooltip = other and "Measured consumption outside the top three estimated output uses."
          or "Estimated amount of the selected material used per second to make this product."
      end
    end
  end

  local stock_state = body.ssk_history_stock_state
  stock_state.visible = not stock
  stock_state.caption = not key and "Select an item to view chest stock history."
    or h and not h.stock_supported and "Chest stock history is available for items. Fluid tanks are outside chest scans."
    or "No completed chest stock scan in the selected period."
  body.ssk_history_stock_title.ssk_history_stock_legend.visible = stock == true
  body.ssk_history_stock_note.visible = stock == true

  local plot_height = height - (width < 620 and 236 or 216)
  local rate_height = math.max(72, math.floor(plot_height * 0.53))
  local stock_height = math.max(68, math.floor(plot_height * 0.47))
  local stock_top = rate_height + PLOT_GAP
  local painter
  if active or stock then
    painter = Canvas.begin(player, chart_width, stock_top + stock_height)
    if active then draw_rates(painter, h, chart_width, rate_height, view) end
    if stock then draw_stock(painter, h, chart_width, stock_height, stock_top) end
  else
    Canvas.clear(player.index)
  end
  camera(player, body.ssk_history_rate_plot, "ssk_history_camera", active and painter, chart_width, rate_height, 0)
  camera(player, body.ssk_history_stock_plot, "ssk_history_stock_camera", stock and painter, chart_width, stock_height, stock_top)
end

function H.on_checked(e, us)
  local tags = e.element.tags
  if not (tags and tags.ssk_ui == "history_view") then return false end
  -- Factorio radiobuttons do not create an exclusive group by themselves.
  us.bal_history_view = tags.view
  return true
end

return H
