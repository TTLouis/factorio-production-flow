local Loc = require("scripts.locale")
-- Balance presentation only. The Sankey renderers continue to use view.lua.
local Balance = require("scripts.balance")
local Graph = require("scripts.graph")
local Groups = require("scripts.groups")
local Watch = require("scripts.watch")

local BU = {}
BU.FILTERS = { "problems", "all", "shortages", "surpluses", "capacity" }
BU.SORTS = { "priority", "groups", "deficit", "empty" }
local FILTER_NAMES = { Loc("balance-problems-only"), Loc("balance-everything"), Loc("balance-supply-activity"), Loc("balance-surpluses"), Loc("balance-spare-capacity") }
local SORT_NAMES = { Loc("balance-priority"), Loc("balance-item-groups"), Loc("balance-biggest-deficit"), Loc("balance-soonest-empty") }
local SHORTAGE = { deficit = true, limited = true, starved = true }
local LIMIT = 200
-- The Balance column is one deep panel, bal_width + 24 wide, laid out like the
-- chart panels: a toolbar strip across the top (12 px at the sides, 8 px above
-- and below, a 40 px row), then the summary, then the column heading and rows
-- in their own bordered box inset 12 px (bal_width wide), as in Transfers.
-- A list that scrolls keeps a 12 px scrollbar lane with an 8 px gutter before
-- it. A list that clearly fits gives both to the item column, so its rows meet
-- the box's right edge as they meet its left one. Headers and rows share widths.
local SCROLLBAR = 12
local PAD_X, PAD_Y, ROW_H, GAP = 12, 8, 40, 8
local LIST_GUTTER = 8
local function list_width(width, lane)
  lane = lane or SCROLLBAR
  return (width or 900) - lane - (lane > 0 and LIST_GUTTER or 0)
end
-- Conservative heights at 100% scale: group headings and one-line rows.
-- Two- and three-line rows (Details, narrow columns) use generous estimates.
local SECTION_H, ROW_EST, NOTE_H = 36, 35, 28
-- Everything above the rows: the tallest toolbar strip, summary, column header
-- and the margins between them, plus the list box's 12 px bottom margin.
local function list_space(height, details)
  return (height or 600) - (2 * PAD_Y + ROW_H + GAP + 28) - (details and 52 or 32) - 100 - PAD_X
end
local function rows_height(display, nfav, empty, details, width, note)
  local row_h = (width or 900) < 550 and 68 or ((details or (width or 900) < 680) and 52 or ROW_EST)
  local h, last = 0, nil
  for i, d in ipairs(display) do
    if i == 1 or d.section ~= last then
      if i > 1 then h = h + GAP end
      if d.section ~= "all" or nfav > 0 or #empty > 0 then h = h + SECTION_H end
      last = d.section
    end
    h = h + row_h
  end
  h = h + #empty * (GAP + SECTION_H + NOTE_H)
  if note then h = h + GAP + NOTE_H end
  return h
end

-- Favourites stay at the top of the list whatever the filters; saved per player.
function BU.favourites(us)
  us.bal_favs = us.bal_favs or {}
  us.bal_favs.items = us.bal_favs.items or {}
  us.bal_favs.groups = us.bal_favs.groups or {}
  return us.bal_favs
end

local function text(parent, caption, tooltip, style)
  return parent.add { type = "label", caption = caption, tooltip = tooltip, style = style }
end

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

local function signed(x, percent)
  local magnitude = math.abs(x)
  local value = percent and string.format("%.0f%%", magnitude * 100) or fmt(magnitude)
  if x == 0 or (percent and value == "0%") then return percent and "0%" or "0" end
  local color = x < 0 and "1,0.45,0.4" or "0.5,0.9,0.5"
  return Loc("balance-formatted", color, Loc.join(x < 0 and "−" or "+", value))
end

local function time(sec)
  if not sec then return "—" end
  if sec >= 3600 then return Loc("balance-h", string.format("%.1f", sec / 3600)) end
  if sec >= 60 then return Loc("balance-min", string.format("%.0f", sec / 60)) end
  return Loc("balance-s", string.format("%.0f", sec))
end

local function pct(x) return x and string.format("%.0f%%", x * 100) or "—" end

local function item_name(key)
  local kind, name = string.match(key, "^(%a+)/(.+)$")
  local proto = kind == "item" and prototypes.item[name] or kind == "fluid" and prototypes.fluid[name]
  return { "", Graph.rt(key), " ", proto and proto.localised_name or name or key }
end

local function group_name(g)
  return { "", g.super_localised_name and { "?", g.super_localised_name, g.super_name } or g.super_name,
    " › ", g.localised_name and { "?", g.localised_name, g.name } or g.name }
end

local function item_tooltip(key, group, warning)
  local tooltip = { "", item_name(key), "\n", group_name(group), "\n", key, Loc("balance-click-to-inspect-this-material") }
  if warning then return { "", tooltip, "\n\n", warning } end
  return tooltip
end

function BU.matches(r, filter)
  if filter == "all" then return true end
  if filter == "shortages" then return SHORTAGE[r.status] == true end
  if filter == "surpluses" then return r.status == "surplus" end
  if filter == "capacity" then return r.status == "overbuilt" end
  return r.status ~= "ok" and r.status ~= "source" and r.status ~= "stored"
end

-- A single column definition controls both headers and cells, including all
-- group sections. Details stack beneath the matching rate, never add columns.
local COLUMNS = {
  { id = "focus", name = "", width = 24 },
  { id = "item", name = Loc("balance-item-fluid"), width = 220 },
  { id = "status", name = Loc("balance-status"), width = 145 },
  { id = "prod", name = Loc("balance-produced"), width = 80, numeric = true,
    help = Loc("balance-measured-production-per-second-on-the-selected") },
  { id = "cons", name = Loc("balance-consumed"), width = 80, numeric = true,
    help = Loc("balance-measured-consumption-per-second-on-the-selected") },
  { id = "net", name = Loc("balance-net-s"), width = 80, numeric = true,
    help = Loc("balance-production-minus-consumption-per-second-positive-surplus") },
  { id = "stock", name = Loc("balance-stock"), width = 85, numeric = true,
    help = Loc("balance-physical-contents-of-ordinary-and-logistic-chests") },
  { id = "eta", name = Loc("balance-empty-in"), width = 90, numeric = true,
    help = Loc("balance-estimated-time-until-chest-stock-is-empty") },
  { id = "netp", name = Loc("balance-net"), width = 70, numeric = true, detail = true,
    help = Loc("balance-net-rate-divided-by-the-larger-of") },
  { id = "pu", name = Loc("balance-producers"), width = 90, numeric = true, detail = true,
    help = Loc("balance-estimated-producer-utilisation-measured-crafts-current-crafting") },
  { id = "cu", name = Loc("balance-consumers"), width = 90, numeric = true, detail = true,
    help = Loc("balance-estimated-consumer-utilisation-measured-crafts-current-crafting") },
  { id = "trend", name = Loc("balance-stock-min"), width = 90, numeric = true, detail = true,
    help = Loc("balance-recent-change-in-chest-stock-per-minute") },
}

local function values(r)
  local st = Balance.STATUS[r.status]
  return {
    item = item_name(r.key), status = r.inactive and Loc("balance-inactive") or Loc("balance-formatted", st.color, st.label),
    prod = fmt(r.prod), cons = fmt(r.cons), net = signed(r.net),
    stock = r.stock and fmt(r.stock) or "—", eta = r.eta and Loc.join("≈ ", time(r.eta)) or "—",
    netp = signed(r.netp, true), pu = pct(r.pu), cu = pct(r.cu),
    trend = r.trend and signed(r.trend) or "—",
  }
end

function BU.hover_details(prod, cons, units, row)
  local net = prod - cons
  local lines = {
    Loc("sankey-produced-consumed", fmt(prod), units, fmt(cons), units),
    Loc.join(Loc("balance-net-s"), "  ", signed(net)),
  }
  if row then
    local v = values(row)
    lines[2] = Loc.join(lines[2], " (", v.netp, ") · ", v.status)
    if row.pu or row.cu then
      lines[#lines + 1] = Loc.join(Loc("balance-producers"), "  ", v.pu, " · ", Loc("balance-consumers"), "  ", v.cu)
    end
    if row.key:sub(1, 5) == "item/" then
      lines[#lines + 1] = Loc.join(Loc("balance-stock"), "  ", v.stock, " · ", Loc("balance-empty-in"), "  ", v.eta)
      if row.trend then lines[#lines + 1] = Loc.join(Loc("balance-stock-min"), "  ", v.trend) end
    end
  end
  return Loc.join_list(lines, "\n")
end

function BU.card_totals(parent, prod, cons, row)
  local table_element = parent.add{type = "table", column_count = 3, style = "ssk_striped_rows"}
  table_element.style.horizontally_stretchable = true
  table_element.style.horizontal_spacing = 8
  table_element.style.vertical_spacing = 0
  table_element.style.top_cell_padding, table_element.style.bottom_cell_padding = 2, 2
  local function add(caption, value, detail, help)
    local label = table_element.add{type = "label", caption = caption}
    label.style.horizontally_stretchable = true
    for _, text in ipairs({value, detail or ""}) do
      local number = table_element.add{type = "label", caption = text, tooltip = help}
      number.style.minimal_width, number.style.horizontal_align = 64, "right"
    end
  end
  local v = row and values(row)
  local reference = math.max(prod, cons)
  add(Loc("balance-made-s"), fmt(prod), row and row.pu and Loc("rate-card-utilisation", v.pu),
    Loc("balance-estimated-producer-utilisation-measured-crafts-current-crafting"))
  add(Loc("balance-used-s"), fmt(cons), row and row.cu and Loc("rate-card-utilisation", v.cu),
    Loc("balance-estimated-consumer-utilisation-measured-crafts-current-crafting"))
  add(Loc("balance-net-s"), signed(prod - cons), signed(reference > 0 and (prod - cons) / reference or 0, true),
    Loc("balance-net-rate-divided-by-the-larger-of"))
  if v then
    if row.key:sub(1, 5) == "item/" then
      add(Loc("balance-stock"), v.stock)
      if row.trend then add(Loc("balance-stock-min"), v.trend) end
      if row.eta then add(Loc("balance-empty-in"), v.eta) end
    end
    parent.add{type = "label", caption = v.status}
  end
end

BU.format_rate = fmt

local function columns(details, width, lane)
  local out = {}
  width = width or 900
  local compact = { focus=52, status=146, prod=60, cons=60, net=62, stock=65, eta=66 }
  local detail = { prod="pu", cons="cu", net="netp", stock="trend" }
  local subhead = { prod=Loc("balance-util"), cons=Loc("balance-util"), net=Loc("balance-net"), stock=Loc("balance-min-2") }
  local total = 0
  for _, col in ipairs(COLUMNS) do
    if not col.detail and not (col.id=="status" and width<680)
      and not ((col.id=="stock" or col.id=="eta") and width<550) then
      local copy = {}
      for k,v in pairs(col) do copy[k]=v end
      copy.width = compact[col.id] or 0
      if width<550 and col.numeric then copy.width=52 end
      if col.id=="prod" then copy.name=Loc("balance-made-s") end
      if col.id=="cons" then copy.name=Loc("balance-used-s") end
      if details and detail[col.id] then
        copy.sub=detail[col.id]
        copy.name=Loc.join(copy.name, "\n", subhead[col.id])
        for _,extra in ipairs(COLUMNS) do
          if extra.id==copy.sub then copy.help=Loc.join(copy.help, "\n\n", extra.help) end
        end
      end
      out[#out+1]=copy
      total=total+copy.width
    end
  end
  for _,col in ipairs(out) do
    -- every cell adds 3 + 3 px padding; the item column takes the rest of the pane
    if col.id=="item" then col.width=math.max(24,list_width(width, lane)-total-#out*6) end
    col.narrow=width<680
    col.stock_in_item=width<550
    col.details=details
  end
  return out
end

local function caption(v, col)
  if col.id=="item" and col.narrow then
    local out={"",v.item,"\n",v.status}
    if col.stock_in_item then
      out[#out+1]=Loc("balance-stock-empty", v.stock, v.eta)
      if col.details then out[#out+1]=Loc("balance-stock-min-2", v.trend) end
    end
    return out
  end
  if col.sub == "netp" or col.sub == "trend" then return Loc.join(v[col.id], "\n", v[col.sub]) end
  if col.sub then return Loc.join(v[col.id], "\n[color=0.65,0.65,0.65]", v[col.sub], "[/color]") end
  return v[col.id]
end

local function grid(parent, name, cols, style)
  -- Factorio's horizontal grid lines can drift a pixel per row. Use row
  -- backgrounds for the body so the shading follows the cell layout.
  local t = parent.add { type = "table", name = name, style = style or "ssk_balance_grid",
    column_count = #cols, draw_horizontal_lines = false, draw_vertical_lines = true }
  t.style.horizontal_spacing = 0
  t.style.left_cell_padding, t.style.right_cell_padding = 3, 3
  t.style.vertical_spacing = 0
  return t
end

-- The column header stays above the scroller, so it remains visible while the
-- rows scroll. It uses the same widths as the row tables beneath it.
local function make_header(parent, cols)
  local header = parent.add { type = "frame", name = "ssk_bal_header", style = "ssk_balance_header", direction = "vertical" }
  -- The strip spans the whole box; the columns keep the rows' widths.
  header.style.width = cols.box_width
  -- Keep one heading row, with paired sublabels only when Details is enabled.
  header.style.height = cols[1].details and 52 or 32
  header.style.bottom_padding = 4
  local t = grid(header, "ssk_bal_columns", cols)
  t.style.top_cell_padding, t.style.bottom_cell_padding = 2, 2
  for _, col in ipairs(cols) do
    local l = text(t, col.name, col.help, "bold_label")
    l.style.width = col.width
    l.style.single_line = false
    l.style.horizontal_align = col.numeric and "right" or "left"
  end
  local line = header.add { type = "line", direction = "horizontal" }
  line.style.width = cols.box_width
  return header
end

local function star_button(parent, set, tags, what)
  local b = parent.add { type = "sprite-button", name = "ssk_bal_fav", style = "tool_button",
    sprite = set and "ssk-star" or "ssk-star-off", tags = tags,
    tooltip = set and Loc("balance-remove-from-favourites", what)
      or Loc("balance-add-to-favourites-always-listed-at-the", what) }
  b.style.width, b.style.height = 24, 24
  return b
end

local function add_row(parent, r, g, cols, fav)
  local cells, v = {}, values(r)
  for _, col in ipairs(cols) do
    local el
    if col.id == "focus" then
      el = parent.add { type = "flow", direction = "horizontal" }
      el.style.horizontal_spacing = 4
      star_button(el, fav, { ssk_ui = "bal_fav", key = r.key }, Loc("balance-this-item"))
      local spec = { type = "sprite-button", name = "ssk_bal_inspect", style = "tool_button", sprite = "utility/search",
        tooltip = Loc("balance-inspect-this-material-on-the-right"), tags = { ssk_ui = "focus_item", key = r.key } }
      local inspect = el.add(spec)
      inspect.style.width, inspect.style.height = 24, 24
    else
      local tooltip = col.id == "item" and item_tooltip(r.key, g)
        or col.id == "status" and Balance.STATUS[r.status].help or col.help
      el = text(parent, caption(v,col), tooltip)
      el.style.horizontal_align = col.numeric and "right" or "left"
      if col.id == "item" then el.tags = { ssk_ui = "bal_material", key = r.key } end
      if col.id == "item" or col.id == "status" then el.style.font = "default-bold" end
      -- Long modded names truncate consistently; the tooltip keeps the full name.
      el.style.single_line = not col.sub and not (col.id=="item" and col.narrow)
    end
    el.style.width = col.width
    cells[col.id] = el
  end
  return cells
end

-- A full-width title bar opens each section: favourites, a group, or the rest.
local function section_header(section, width, caption, star)
  local header=section.add {type="frame",name="ssk_bal_group_header",
    style="repeated_subheader_frame",direction="horizontal"}
  header.style.width=width
  header.style.left_padding,header.style.right_padding=8,8
  header.style.vertical_align="center"
  if star then star_button(header, star.set, star.tags, Loc("balance-this-group")) end
  local h=header.add{type="label",caption=caption,tooltip=caption,style="caption_label"}
  if star then h.style.left_margin=8 end
  h.style.width=width-16-(star and 32 or 0)
  h.style.single_line=true
  return header
end

-- Display order: favourite items, favourite groups (whole), then the filtered
-- list. Favourites ignore Show / Group and do not count towards the row limit.
local function arrange(favs, rows, filtered, by_key, info, order)
  local display, used = {}, {}
  local function push(r, section)
    used[r.key] = true
    display[#display + 1] = { row = r, section = section }
  end
  local present, fav_items, missing = {}, {}, {}
  for _, r in ipairs(rows) do
    present[r.key] = true
    if favs.items[r.key] then fav_items[#fav_items + 1] = r end
  end
  for key in pairs(favs.items) do if not present[key] then missing[#missing + 1] = key end end
  table.sort(missing)
  for _, key in ipairs(missing) do
    fav_items[#fav_items + 1] = { key = key, prod = 0, cons = 0, net = 0, netp = 0, status = "ok", inactive = true }
  end
  Balance.sort(fav_items, order)
  for _, r in ipairs(fav_items) do push(r, "fav") end
  local fav_groups = {}
  for gid in pairs(favs.groups) do fav_groups[#fav_groups + 1] = info(gid) end
  table.sort(fav_groups, Groups.less)
  local empty = {}
  for _, g in ipairs(fav_groups) do
    local members = {}
    for _, r in ipairs(rows) do
      if by_key[r.key].id == g.id and not used[r.key] then members[#members + 1] = r end
    end
    table.sort(members, function(a, b)
      local oa, ob = Balance.STATUS[a.status].order, Balance.STATUS[b.status].order
      if oa ~= ob then return oa < ob end
      return a.key < b.key
    end)
    Balance.sort(members, order)
    for _, r in ipairs(members) do push(r, Loc.join("fg:", g.id)) end
    if #members == 0 then empty[#empty + 1] = { group = g, before = #display + 1 } end
  end
  local nfav = #display
  local normal = {}
  for _, r in ipairs(filtered) do
    if not used[r.key] and not favs.groups[by_key[r.key].id] then normal[#normal + 1] = r end
  end
  Balance.sort(normal, order)
  return display, normal, nfav, empty
end

-- Themes group the existing indicators; their individual meanings and help stay visible.
local SUMMARY_GROUPS = {
  { id = "under", label = Loc("balance-underproducing"), color = "1,0.45,0.4", ids = { "deficit", "limited", "starved" },
    help = Loc("balance-deficits-and-activity-warnings-a-supply-warning") },
  { id = "ok", label = Loc("balance-ok"), color = "0.5,0.9,0.5", ids = { "ok", "source", "stored" },
    help = Loc("balance-no-detected-rate-or-utilisation-warning-source") },
  { id = "over", label = Loc("balance-overproducing"), color = "1,0.85,0.35", ids = { "surplus", "overbuilt" },
    help = Loc("balance-measured-surplus-or-spare-producer-capacity-spare") },
}

function BU.fill(player, c, us, scope, only_auto)
  local rows, secs, stock, stock_known, totals = Balance.rows(us.sidx, us.period)
  local favs = BU.favourites(us)
  local warnings = Watch.evaluate(player, us, secs, stock, stock_known, totals)
  local previous = c.ssk_bal_root
  local live_reuse = only_auto and previous and previous.tags.visible_keys
  local groups, seen, by_key, counts = {}, {}, {}, {}
  local function info(id)
    seen[id] = seen[id] or Groups.info(player.index, id)
    return seen[id]
  end
  local function group_of(key)
    by_key[key] = by_key[key] or info(Groups.of(player.index, key))
    return by_key[key]
  end
  if not live_reuse then
    for _, r in ipairs(rows) do
      local id = Groups.of(player.index, r.key)
      if not seen[id] then seen[id] = Groups.info(player.index, id); groups[#groups + 1] = seen[id] end
      by_key[r.key] = seen[id]
    end
    table.sort(groups, Groups.less)
    -- A saved filter survives temporary inactivity; it can still be cleared.
    if us.bal_group and not seen[us.bal_group] then
      groups[#groups + 1] = info(us.bal_group)
      table.sort(groups, Groups.less)
    end
  end
  local filtered = {}
  local nfav, empty, display, normal, limit, matching_count = 0, {}, nil, {}, 0, 0
  if live_reuse then
    local current = {}
    for _, r in ipairs(rows) do
      current[r.key] = r
      if not us.bal_group or Groups.of(player.index, r.key) == us.bal_group then
        counts[r.status] = (counts[r.status] or 0) + 1
      end
    end
    display = {}
    for _, key in ipairs(previous.tags.visible_keys) do
      display[#display + 1] = { row = current[key] or { key = key, prod = 0, cons = 0, net = 0, netp = 0, status = "ok", inactive = true } }
    end
  else
    for _, r in ipairs(rows) do
      if not us.bal_group or by_key[r.key].id == us.bal_group then
        counts[r.status] = (counts[r.status] or 0) + 1
        if BU.matches(r, us.bal_filter) then filtered[#filtered + 1] = r end
      end
    end
    if us.bal_sort == "groups" then
      table.sort(filtered, function(a, b)
        local ga, gb = by_key[a.key], by_key[b.key]
        if ga.id ~= gb.id then return Groups.less(ga, gb) end
        local oa, ob = Balance.STATUS[a.status].order, Balance.STATUS[b.status].order
        if oa ~= ob then return oa < ob end
        return a.key < b.key
      end)
    end
    display, normal, nfav, empty = arrange(favs, rows, filtered, by_key, info, us.bal_sort)
    matching_count = nfav + #normal
    limit = math.min(#normal, us.bal_limit or LIMIT)
    for i = 1, limit do
      local r = normal[i]
      display[#display + 1] = { row = r, section = us.bal_sort == "groups" and Loc.join("g:", by_key[r.key].id) or "all" }
    end
  end
  local shown = #display
  local list = {}
  for i, d in ipairs(display) do list[i] = d.row end
  local signature
  if not live_reuse then
    signature = { tostring(us.bal_height), tostring(us.bal_width), tostring(us.bal_details), us.bal_sort or "priority", us.bal_filter or "problems", us.bal_group or "", tostring(shown), tostring(matching_count), tostring(#rows == 0) }
    for _, g in ipairs(groups) do signature[#signature + 1] = g.id end
    local fav_keys = {}
    for key in pairs(favs.items) do fav_keys[#fav_keys + 1] = Loc.join("*", key) end
    for gid in pairs(favs.groups) do fav_keys[#fav_keys + 1] = Loc.join("#", gid) end
    table.sort(fav_keys)
    for _, k in ipairs(fav_keys) do signature[#signature + 1] = k end
    for _, e in ipairs(empty) do signature[#signature + 1] = Loc.join("empty:", e.group.id) end
    for i = 1, shown do
      local r = list[i]
      signature[#signature + 1] = Loc.join(r.key, ":", r.status, ":", (display[i].section or ""))
    end
    signature = Loc.join_list(signature, "|")
  end

  -- Reuse existing cells while the visible rows stay the same. Live sampling
  -- updates values without destroying the table, dropdowns or scroll position.
  local same = live_reuse or (c.ssk_bal_root and c.ssk_bal_root.tags.signature == signature)
  local root, summaries, summary_heads, cells, refresh
  -- Hide the scrollbar lane only with a full row to spare. The pane still scrolls
  -- with the mouse wheel, so a low estimate can never clip a row. Live updates
  -- reuse the built table, so they keep the lane it was built with.
  local lane = SCROLLBAR
  if same then lane = c.ssk_bal_root.tags.lane or SCROLLBAR
  elseif limit >= #normal and rows_height(display, nfav, empty, us.bal_details, us.bal_width, #normal == 0) + ROW_EST
    <= list_space(us.bal_height, us.bal_details) then lane = 0 end
  local cols = columns(us.bal_details, us.bal_width, lane)
  local list_w = list_width(us.bal_width, lane)
  cols.list_width = list_w
  cols.box_width = us.bal_width or 900
  local gutter = lane > 0 and LIST_GUTTER or 0
  if same then
    root = c.ssk_bal_root
    refresh = root.ssk_bal_strip.ssk_bal_controls.ssk_bal_refresh
    summaries, summary_heads, cells = {}, {}, {}
    for _, group in ipairs(SUMMARY_GROUPS) do
      local column = root.ssk_bal_summary[Loc.join("ssk_bal_", group.id)]
      summary_heads[group.id] = column.ssk_bal_theme
      for _, id in ipairs(group.ids) do summaries[id] = column[Loc.join("ssk_bal_", id)] end
    end
    for i = 1, shown do
      local entry = root.ssk_bal_list.ssk_bal_items[Loc.join("ssk_bal_section_", i)]
      if entry then -- Sections are named for the first row they contain.
        local t = entry.ssk_bal_table
        -- Reading children copies the whole array through the Factorio API.
        -- Cache it once, not once for every cell in the table.
        local children = t.children
        local offset = 0
        local j = i
        while j <= shown and (j == i or not root.ssk_bal_list.ssk_bal_items[Loc.join("ssk_bal_section_", j)]) do
          cells[j] = {}
          for k, col in ipairs(cols) do cells[j][col.id] = children[offset + k] end
          offset = offset + #cols
          j = j + 1
        end
      end
    end
  else
    c.clear()
    local visible_keys={}; for i=1,shown do visible_keys[i]=list[i].key end
    root = c.add { type = "frame", name = "ssk_bal_root", style = "inside_deep_frame", direction = "vertical",
      tags = { signature = signature, visible_keys=visible_keys, lane = lane } }
    local panel_width = (us.bal_width or 900) + 24
    root.style.width = panel_width
    root.style.height = us.bal_height or 600
    root.style.padding = 0
    local strip = root.add { type = "frame", name = "ssk_bal_strip", style = "subheader_frame", direction = "vertical" }
    strip.style.horizontally_stretchable = true
    strip.style.left_padding, strip.style.right_padding = PAD_X, PAD_X
    strip.style.top_padding, strip.style.bottom_padding = PAD_Y, PAD_Y
    local toolbar_width = panel_width - 2 * PAD_X
    local toolbar = strip.add { type = "flow", name = "ssk_bal_controls", direction = "horizontal" }
    -- The same 8 px gap between controls as the chart toolbars.
    local spacing = 8
    toolbar.style.vertical_align = "center"
    toolbar.style.horizontal_spacing = spacing
    toolbar.style.width = toolbar_width
    toolbar.style.height = ROW_H
    local show_label_width, group_label_width, order_label_width = 38, 44, 40
    local labels_width = show_label_width + group_label_width + order_label_width + 3 * spacing
    local details_width = 76
    -- Allow for the four gaps between the three pickers, spacer and refresh button.
    local picker_budget = toolbar_width - 8 - 28 - 4 * spacing
    if us.bal_group then picker_budget = picker_budget - 24 - spacing end
    local labelled_width = 3 * 120 + labels_width
    local inline_details = picker_budget >= labelled_width + details_width + spacing
    if inline_details then picker_budget = picker_budget - details_width - spacing end
    local show_labels = picker_budget >= labelled_width
    if show_labels then picker_budget = picker_budget - labels_width end
    local picker_width = math.max(36, math.min(134, math.floor(picker_budget / 3)))

    if show_labels then text(toolbar, Loc("balance-show")).style.width = show_label_width end
    local fi = 1
    for i, id in ipairs(BU.FILTERS) do if id == us.bal_filter then fi = i end end
    local filter = toolbar.add { type = "drop-down", items = FILTER_NAMES, selected_index = fi,
      tags = { ssk_ui = "bal_filter" }, tooltip = Loc("balance-show-2", FILTER_NAMES[fi]) }
    filter.style.width = picker_width

    if show_labels then text(toolbar, Loc("balance-group")).style.width = group_label_width end
    local names, gi = { Loc("balance-all-groups") }, 1
    us.bal_group_ids = {}
    for i, g in ipairs(groups) do
      names[i + 1] = group_name(g); us.bal_group_ids[i + 1] = g.id
      if g.id == us.bal_group then gi = i + 1 end
    end
    local picker = toolbar.add { type = "drop-down", items = names, selected_index = gi,
      tags = { ssk_ui = "bal_group" }, tooltip = { "", Loc("balance-material-group"), names[gi] } }
    picker.style.width = math.max(36, math.min(240, picker_budget - 2 * picker_width))
    if us.bal_group then
      star_button(toolbar, favs.groups[us.bal_group], { ssk_ui = "bal_fav_group", gid = us.bal_group }, Loc("balance-this-group"))
    end

    if show_labels then text(toolbar, Loc("balance-order")).style.width = order_label_width end
    local sort_index = 1
    for i, id in ipairs(BU.SORTS) do if id == us.bal_sort then sort_index = i end end
    toolbar.add { type = "drop-down", items = SORT_NAMES, selected_index = sort_index,
      tags = { ssk_ui = "bal_sort" }, tooltip = Loc("balance-sort-by", SORT_NAMES[sort_index]) }.style.width = picker_width

    local spacer = toolbar.add { type = "empty-widget" }
    spacer.style.horizontally_stretchable = true
    spacer.style.minimal_width = 8
    local details_row = toolbar
    local strip_height = 2 * PAD_Y + ROW_H
    if not inline_details then
      -- A narrow column moves Details to a second 28 px toolbar row.
      details_row = strip.add { type = "flow", direction = "horizontal" }
      details_row.style.width = toolbar_width
      details_row.style.height = 28
      details_row.style.top_margin = GAP
      details_row.style.vertical_align = "center"
      details_row.add { type = "empty-widget" }.style.horizontally_stretchable = true
      strip_height = strip_height + GAP + 28
    end
    strip.style.height = strip_height
    details_row.add { type = "checkbox", caption = Loc("balance-details"), state = us.bal_details == true, tags = { ssk_ui = "bal_details" },
      tooltip = Loc("balance-show-net-percentage-producer-consumer-utilisation-and") }
    refresh = toolbar.add { type = "sprite-button", name = "ssk_bal_refresh", style = "tool_button", sprite = "utility/refresh",
      tags = { ssk_ui = "bal_update" }, tooltip = Loc("balance-refresh-table") }
    local summary = root.add { type = "table", name = "ssk_bal_summary", column_count = 3 }
    summary.style.horizontal_spacing = GAP
    summary.style.left_margin, summary.style.right_margin = PAD_X, PAD_X
    summary.style.top_margin = PAD_Y
    summary.vertical_centering = false
    local width = math.floor((panel_width - 2 * PAD_X - 2 * GAP) / 3)
    summaries, summary_heads = {}, {}
    for _, group in ipairs(SUMMARY_GROUPS) do
      local column = summary.add { type = "flow", name = Loc.join("ssk_bal_", group.id), direction = "vertical" }
      column.style.width = width
      column.style.vertical_spacing = 0
      local heading = column.add { type = "label", name = "ssk_bal_theme", tooltip = group.help }
      heading.style.font = "default-bold"
      heading.style.width = width
      heading.style.single_line = true
      summary_heads[group.id] = heading
      for _, id in ipairs(group.ids) do
        local label = column.add { type = "label", name = Loc.join("ssk_bal_", id), tooltip = Balance.STATUS[id].help }
        label.style.width = width
        label.style.font = "default-small"
        label.style.single_line = true
        summaries[id] = label
      end
    end
    -- Only the item list scrolls; filters, summary, column header and pagination
    -- stay visible. A deep frame bounds the list and a raised header clearly
    -- separates fixed headings from the independently scrolling rows.
    -- The heading row and rows share one bordered box inset 12 px, like the
    -- Transfers Items and History entity lists. It stretches to the panel's foot.
    local list_flow = root.add { type = "frame", name = "ssk_bal_list", style = "inside_deep_frame", direction = "vertical" }
    list_flow.style.width = cols.box_width
    list_flow.style.padding = 0
    list_flow.style.left_margin, list_flow.style.top_margin = PAD_X, PAD_Y
    list_flow.style.bottom_margin = limit < #normal and PAD_Y or PAD_X
    list_flow.style.vertically_stretchable = true
    if shown > 0 then make_header(list_flow, cols) end
    local items = list_flow.add { type = "scroll-pane", name = "ssk_bal_items", style = "naked_scroll_pane",
      horizontal_scroll_policy = "never",
      vertical_scroll_policy = lane > 0 and "auto-and-reserve-space" or "dont-show-but-allow-scrolling" }
    items.style.width = cols.box_width
    items.style.vertically_stretchable = true
    items.style.minimal_height = 0
    cells = {}
    local t, last
    local e = 1
    local function empty_groups(before)
      while empty[e] and empty[e].before <= before do
        local g = empty[e].group
        local section = items.add { type = "flow", name = Loc.join("ssk_bal_empty_", e), direction = "vertical" }
        section.style.vertical_spacing = 0
        section.style.right_padding = gutter
        section.style.top_margin = #items.children > 1 and 8 or 0
        section_header(section, list_w, group_name(g), { set = true, tags = { ssk_ui = "bal_fav_group", gid = g.id } })
        local note = text(section, Loc("balance-no-items-in-this-group-right-now"))
        note.style.font_color = { 0.65, 0.65, 0.65 }
        note.style.left_margin, note.style.top_margin, note.style.bottom_margin = 8, 4, 4
        e = e + 1
      end
    end
    for i = 1, shown do
      empty_groups(i)
      local r, d = list[i], display[i]
      local g = group_of(r.key)
      if not t or last ~= d.section then
        local section = items.add { type = "flow", name = Loc.join("ssk_bal_section_", i), direction = "vertical" }
        section.style.vertical_spacing = 0
        section.style.right_padding = gutter
        section.style.top_margin = #items.children > 1 and 8 or 0
        if d.section == "fav" then
          section_header(section, list_w, Loc("balance-favourites"))
        elseif d.section:sub(1, 3) == "fg:" then
          section_header(section, list_w, group_name(g), { set = true, tags = { ssk_ui = "bal_fav_group", gid = g.id } })
        elseif d.section:sub(1, 2) == "g:" then
          section_header(section, list_w, group_name(g), { set = false, tags = { ssk_ui = "bal_fav_group", gid = g.id } })
        elseif nfav > 0 or #empty > 0 then
          section_header(section, list_w, Loc("balance-all-other-items"))
        end
        t = grid(section, "ssk_bal_table", cols, "ssk_striped_rows")
      end
      cells[i] = add_row(t, r, g, cols, favs.items[r.key] == true)
      last = d.section
    end
    empty_groups(math.huge)
    if #normal == 0 then
      local note = text(items, #rows == 0 and Loc("balance-no-measured-activity-or-chest-stock-yet")
        or Loc("balance-no-items-match-this-view-try-everything"))
      if shown > 0 then note.style.top_margin = 8 end
    end
    if limit < #normal then
      -- the one text button: a long-form command centred under the list, as vanilla does
      local more = root.add { type = "flow", direction = "horizontal" }
      more.style.horizontal_align = "center"
      more.style.horizontally_stretchable = true
      more.style.bottom_margin = PAD_X
      more.add { type = "button", caption = Loc("balance-show-200-more"), tags = { ssk_ui = "bal_more" },
        tooltip = Loc("balance-add-the-next-200-matching-rows-to") }
    end
  end
  for _, group in ipairs(SUMMARY_GROUPS) do
    local total = 0
    for _, id in ipairs(group.ids) do total = total + (counts[id] or 0) end
    summary_heads[group.id].caption = Loc("balance-formatted-2", group.color, group.label, string.format("%d", total))
  end
  for id, el in pairs(summaries) do
    local st = Balance.STATUS[id]
    el.caption = Loc("balance-formatted-2", st.color, st.label, string.format("%d", counts[id] or 0))
  end
  for i = 1, shown do
    local r = list[i]
    local v = values(r)
    local group = group_of(r.key)
    if favs.items[r.key] or favs.groups[group.id] then
      local warning = warnings and warnings[r.key]
      if warning then v.item = { "", "[img=utility/warning_icon] ", v.item } end
      cells[i].item.tooltip = item_tooltip(r.key, group, warning)
    end
    for _,col in ipairs(cols) do
      if col.id~="focus" then cells[i][col.id].caption=caption(v,col) end
    end
    if cells[i].status then
      cells[i].status.tooltip=list[i].inactive and Loc("balance-no-measured-activity-in-the-current-window")
        or Balance.STATUS[list[i].status].help
    end
    cells[i].focus.ssk_bal_inspect.toggled = us.bal_fx and us.bal_fx.focus == list[i].key or false
  end
  refresh.tooltip = Loc("balance-refresh-table")
  return list[1] and list[1].key
end

return BU
