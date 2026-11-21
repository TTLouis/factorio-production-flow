local Loc = require("scripts.locale")
local Rail = require("scripts.cell_rail")
local Axis = require("scripts.transfer_history_axis")
local Layout = require("scripts.transfer_history_layout")
local Plot = require("scripts.gui_plot")
local Colors = require("shared.plot_colors")
local Sampler = require("scripts.sampler")

local History = {}
local LEFT = 132
local LOAD, DROP = Colors.ribbon_in_1, Colors.ribbon_out_1

local function label(parent, caption, style, width)
  local element = parent.add { type = "label", caption = caption, style = style or "label" }
  if width then element.style.width = width end
  return element
end

local function quality_icon(item)
  local quality = item.quality and item.quality ~= "normal" and prototypes.quality and prototypes.quality[item.quality]
  return quality and " [img=quality/" .. item.quality .. "]" or ""
end

function History.material_name(item, compact)
  local prototype = prototypes[item.kind] and prototypes[item.kind][item.name]
  local icon = prototype and "[img=" .. item.kind .. "/" .. item.name .. "]" or ""
  if compact and prototype then return icon .. quality_icon(item) end
  return Loc.join(prototype and icon .. " " or "", prototype and prototype.localised_name or item.name, quality_icon(item))
end

function History.material_count(item)
  local amount = item.count
  local magnitude = math.abs(amount)
  if magnitude >= 1000 then
    local divisor, suffix = 1000, "balance-k"
    if magnitude >= 1000000000 then divisor, suffix = 1000000000, "history-g"
    elseif magnitude >= 1000000 then divisor, suffix = 1000000, "balance-m" end
    local scaled = amount / divisor
    local places = math.abs(scaled) < 10 and 2 or math.abs(scaled) < 100 and 1 or 0
    local rounded = tonumber(string.format("%." .. places .. "f", scaled))
    if math.abs(rounded) >= 1000 and divisor < 1000000000 then
      divisor = divisor * 1000
      suffix = divisor == 1000000 and "balance-m" or "history-g"
      rounded, places = amount / divisor, 2
    end
    local text = string.format("%." .. places .. "f", rounded)
    if places > 0 then text = text:gsub("0+$", ""):gsub("%.$", "") end
    return suffix == "balance-k" and Loc("rail-count-k", text)
      or suffix == "balance-m" and Loc("balance-m", text) or Loc("history-g", text)
  end
  return item.kind == "item" and string.format("%.0f", item.count) or string.format("%.5g", item.count)
end

function History.material(item)
  return Loc.join(History.material_name(item), "  ", History.material_count(item))
end

function History.stop_captions(stops)
  local counts, captions = {}, {}
  for _, stop in pairs(stops) do
    local name = Rail.name(stop)
    counts[name] = (counts[name] or 0) + 1
  end
  for unit, stop in pairs(stops) do
    local name = Rail.name(stop)
    local p = stop.entity.valid and stop.entity.position
    captions[unit] = counts[name] > 1 and p and Loc("rail-stop-location", name, math.floor(p.x), math.floor(p.y)) or name
  end
  return captions
end

function History.reset(state)
  state.from, state.to, state.event, state.expanded, state.page = nil, nil, nil, nil, nil
end

function History.on_switch(el, state)
  local axis = Axis.selection(el)
  if not axis then return false end
  state.axis = axis
  History.reset(state)
  return true
end

function History.on_click(tags, state)
  local action = tags.ssk_rail
  if action == "clear_range" then History.reset(state)
  elseif action == "interval" then state.from, state.to, state.event, state.expanded = tags.from, tags.to, nil, nil
  elseif action == "exchange" then state.from, state.to, state.event, state.expanded = nil, nil, tags.id, tags.id
  elseif action == "visit" then state.expanded = state.expanded ~= tags.id and tags.id or nil
  elseif action == "pages" then
    History.reset(state)
    state.page = tags.page
  else return false end
  return true
end

local function toolbar_button(parent, sprite, tip, tags)
  return parent.add { type = "sprite-button", style = "tool_button", sprite = sprite, tooltip = tip, tags = tags }
end

local function hit(parent, x, y, width, height, tooltip, tags)
  local target = parent.add { type = "sprite", sprite = "ssk-node-hit", resize_to_sprite = false, tooltip = tooltip, tags = tags }
  local style = target.style
  style.width, style.height = width, height
  style.left_margin, style.top_margin, style.bottom_margin = x, y, -height
  local reset = parent.add { type = "empty-widget", ignored_by_interaction = true }
  reset.style.width, reset.style.height, reset.style.top_margin = 0, 0, -y
end

local function make_timeline(rows, state, from, to, width)
  local bands, loaded, unloaded = {}, 0, 0
  local events = state.axis == "events"
  local step = math.max(1, math.floor((to - from) / 10 + 0.5))
  local start_tick = math.floor(from / step) * step
  if not events then
    for start = start_tick, to - 1, step do
      bands[#bands + 1] = { from = start, to = start + step, loaded = 0, unloaded = 0 }
    end
  end
  for i = #rows, 1, -1 do
    local row = rows[i]
    if not row.pending then
      local up, down = #row.loaded > 0 and 1 or 0, #row.unloaded > 0 and 1 or 0
      loaded, unloaded = loaded + up, unloaded + down
      if events then
        if up + down > 0 then bands[#bands + 1] = { loaded = up, unloaded = down, row = row } end
      else
        local band = bands[math.min(#bands, math.floor((row.tick - start_tick) / step) + 1)]
        if band then band.loaded, band.unloaded = band.loaded + up, band.unloaded + down end
      end
    end
  end
  local slots = math.max(1, math.floor((width - LEFT - 18) / 36))
  local pages = events and math.max(1, math.ceil(#bands / slots)) or 1
  local page = math.max(1, math.min(state.page or pages, pages))
  local first, last = events and ((page - 1) * slots + 1) or 1, events and math.min(page * slots, #bands) or #bands
  return bands, loaded, unloaded, first, last, page, pages, slots
end

local function timeline(parent, rows, state, from, to, width, height)
  local bands, loaded, unloaded, first, last, page, pages, slots = make_timeline(rows, state, from, to, width)
  local events = state.axis == "events"
  local strip = Layout.strip(parent)
  label(strip, Loc("transfers-cargo-timeline"), "subheader_caption_label")
  label(strip, events and Loc("rail-event-slots") or Loc("rail-time-buckets"), "grey_label")
  strip.add { type = "empty-widget" }.style.horizontally_stretchable = true
  if events and pages > 1 then
    toolbar_button(strip, "utility/left_arrow", Loc("transfer-exchanges-previous"),
      { ssk_rail = "pages", page = page - 1 }).enabled = page > 1
    label(strip, Loc("se-ui-page", page, pages), "grey_label")
    toolbar_button(strip, "utility/right_arrow", Loc("transfer-exchanges-next"),
      { ssk_rail = "pages", page = page + 1 }).enabled = page < pages
  end
  Axis.add(strip, state.axis, Loc("rail-axis-tip"))
  label(strip, Loc("transfers-loaded-unloaded", loaded, unloaded), "subheader_semibold_label")

  local chart = parent.add { type = "flow", direction = "vertical" }
  chart.style.width, chart.style.height, chart.style.vertical_spacing = width, height, 0
  local p = Plot.begin(chart, width, height, "ssk_rail_timeline")
  p.root.style.bottom_margin = -height
  local right, top, bottom = width - 14, 8, height - 22
  local mid = math.floor((top + bottom) / 2)
  local peak = 1
  for i = first, last do peak = math.max(peak, bands[i].loaded, bands[i].unloaded) end
  local scale = (mid - top - 5) / peak
  for _, y in ipairs({mid - peak * scale, mid, mid + peak * scale}) do
    p.line(LEFT, y, right, y, y == mid and Colors.platform_axis or Colors.grid)
    p.text(LEFT - 6, y, y == mid and "0" or tostring(peak), Colors.platform_tick, "right")
  end
  p.rect(8, math.floor((mid + top) / 2) - 4, 8, 8, LOAD)
  p.rect(8, math.floor((mid + bottom) / 2) - 4, 8, 8, DROP)
  p.text(22, (mid + top) / 2, Loc("rail-loaded-short"), Colors.platform_tick)
  p.text(22, (mid + bottom) / 2, Loc("rail-unloaded-short"), Colors.platform_tick)
  for i = first, last do
    local band = bands[i]
    local x1, x2, selected, tags, caption
    if events then
      local slot = (right - LEFT) / slots
      x1, x2 = right - (last - i + 1) * slot, right - (last - i) * slot
      selected = state.event == band.row.id
      tags, caption = { ssk_rail = "exchange", id = band.row.id }, Loc("rail-visit-train", band.row.train)
      if i == first or i == last or (i - first) % 3 == 0 then
        p.text((x1 + x2) / 2, bottom + 11, "#" .. i, Colors.platform_tick, "center")
      end
    else
      x1 = LEFT + (right - LEFT) * (math.max(band.from, from) - from) / (to - from)
      x2 = LEFT + (right - LEFT) * (math.min(band.to, to) - from) / (to - from)
      selected = state.from == band.from and state.to == band.to
      tags, caption = { ssk_rail = "interval", from = band.from, to = band.to },
        Loc("rail-age", Sampler.duration(math.max(0, math.ceil((to - band.from) / 60))))
    end
    if selected then p.rect(x1, top, x2 - x1, bottom - top, Colors.platform_selection) end
    local inset = math.max(1, math.floor((x2 - x1) * 0.12))
    if band.loaded > 0 then p.rect(x1 + inset, mid - scale * band.loaded, x2 - x1 - inset * 2, scale * band.loaded, LOAD) end
    if band.unloaded > 0 then p.rect(x1 + inset, mid + 1, x2 - x1 - inset * 2, scale * band.unloaded, DROP) end
    hit(chart, math.floor(x1), top, math.max(1, math.floor(x2) - math.floor(x1)), bottom - top,
      Loc.join(caption, "\n", Loc("transfers-loaded-unloaded", band.loaded, band.unloaded)), tags)
  end
  if not events then
    for i = 0, 5 do
      local x = LEFT + (right - LEFT) * i / 5
      local age = math.floor((to - from) * (1 - i / 5) / 60 + 0.01)
      p.text(x, bottom + 11, age > 0 and Loc("rail-age", Sampler.duration(age)) or Loc("rail-now"),
        Colors.platform_tick, i == 5 and "right" or "center")
    end
  end
end

local function cargo_preview(row)
  if row.pending then return "—" end
  local result, seen, count = {""}, {}, 0
  for _, group in ipairs({row.unloaded, row.loaded}) do
    for _, item in ipairs(group) do
      local key = item.name .. "/" .. (item.quality or "")
      if not seen[key] then
        seen[key], count = true, count + 1
        if count <= 6 and prototypes[item.kind] and prototypes[item.kind][item.name] then
          result[#result + 1] = "[img=" .. item.kind .. "/" .. item.name .. "] "
        end
      end
    end
  end
  if count == 0 then return Loc("rail-no-exchange") end
  return result
end

local function table_label(row, caption, width, style)
  local entry = label(row, caption, style, width)
  entry.style.single_line = true
  return entry
end

local function visit_log(parent, rows, names, state, width, height, now)
  local title = Layout.strip(parent)
  label(title, Loc("rail-visits"), "subheader_caption_label")
  title.add { type = "empty-widget" }.style.horizontally_stretchable = true
  if state.event or state.from then
    toolbar_button(title, "utility/reset", Loc("rail-clear-range"), { ssk_rail = "clear_range" })
  end
  local usable = width - Layout.SCROLL_GUTTER - 24
  local narrow = math.floor(usable / 7)
  local widths = { narrow, narrow, narrow * 2, usable - 5 * narrow - 56, narrow }
  local headers = Layout.columns(parent, "ssk_rail_headings", width - Layout.SCROLL_GUTTER)
  headers.add { type = "empty-widget" }.style.width = 30
  for i, caption in ipairs({ Loc("transfer-axis-time"), Loc("transfers-direction"), Loc("rail-stop-train"),
    Loc("transfers-cargo"), Loc("rail-status") }) do table_label(headers, caption, widths[i], "caption_label") end
  local pane = parent.add { type = "scroll-pane", name = "ssk_rail_visits", style = "naked_scroll_pane",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
  pane.style.width, pane.style.height = width, height
  local count = 0
  for _, visit in ipairs(rows) do
    local within = (not state.event or visit.id == state.event)
      and (not state.from or (visit.tick >= state.from and visit.tick < state.to))
    if within and count < 100 then
      count = count + 1
      local row = pane.add { type = "flow", direction = "horizontal" }
      row.style.vertical_align, row.style.height = "center", 28
      local expandable = not visit.pending and #visit.loaded + #visit.unloaded > 0
      if expandable then
        toolbar_button(row, state.expanded == visit.id and "utility/collapse" or "utility/expand",
          Loc("rail-expand-cargo"), { ssk_rail = "visit", id = visit.id })
      else
        row.add { type = "empty-widget" }.style.width = 26
      end
      local age = math.max(0, math.floor((now - visit.tick) / 60))
      local loads = not visit.pending and #visit.loaded > 0
      local drops = not visit.pending and #visit.unloaded > 0
      local direction = loads and (drops and Loc("rail-both") or Loc("rail-loaded-short"))
        or drops and Loc("rail-unloaded-short") or "—"
      table_label(row, Loc("rail-age", Sampler.duration(age)), widths[1])
      table_label(row, direction, widths[2])
      table_label(row, Loc.join(names[visit.stop], "  ·  ", Loc("rail-visit-train", visit.train)), widths[3])
      table_label(row, cargo_preview(visit), widths[4])
      table_label(row, visit.pending and Loc("rail-awaiting") or Loc("rail-completed"), widths[5])
      if expandable and state.expanded == visit.id then
        local detail = pane.add { type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" }
        detail.style.horizontally_stretchable = true
        for _, group in ipairs({ { visit.loaded, Loc("rail-net-loaded") }, { visit.unloaded, Loc("rail-net-unloaded") } }) do
          if #group[1] > 0 then
            label(detail, group[2], "caption_label")
            for _, item in ipairs(group[1]) do label(detail, History.material(item)) end
          end
        end
      end
    end
  end
  if count == 0 then label(pane, Loc("rail-no-visits"), "grey_label") end
  if count == 100 then label(pane, Loc("rail-showing-newest"), "grey_label") end
end

function History.render(_, parent, stops, units, state, period, width, height)
  local picker = Layout.strip(parent)
  label(picker, Loc("rail-stop"), "subheader_caption_label")
  local ids, captions, selected = {0}, {Loc("rail-all-stops")}, 1
  local names = History.stop_captions(stops)
  for _, unit in ipairs(units) do
    ids[#ids + 1], captions[#captions + 1] = unit, names[unit]
    if state.filter == unit then selected = #ids end
  end
  if selected == 1 and state.filter and state.filter ~= 0 then state.filter = nil; History.reset(state) end
  picker.add { type = "drop-down", items = captions, selected_index = selected,
    tags = { ssk_rail_select = "history", ids = ids } }.style.maximal_width = 290
  local now = game.tick
  local from, to = math.max(0, now - period * 60), now + 1
  local filtered = selected == 1 and stops or { [ids[selected]] = stops[ids[selected]] }
  local rows, truncated = Rail.read_history(filtered, from)
  if truncated then label(picker, Loc("rail-history-truncated"), "grey_label") end
  local chart_height = Layout.plot_height(height)
  timeline(parent, rows, state, from, to, width, chart_height)
  visit_log(parent, rows, names, state, width, Layout.log_height(height, chart_height, Layout.STRIP_HEIGHT), now)
end

return History
