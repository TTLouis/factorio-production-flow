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
-- The item list pane is bal_width + 24 wide and always reserves its scrollbar,
-- with an 8 px inner gutter between the last column and the scrollbar.
-- Headers and rows share the same content width.
local SCROLLBAR = 12
local LIST_PADDING = 4
local LIST_GUTTER = 8
local function list_width(width) return (width or 900) + 24 - SCROLLBAR - 2 * LIST_PADDING - LIST_GUTTER end

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

local function signed(x)
  if x == 0 then return "0" end
  return Loc.join((x > 0 and "+" or "−"), fmt(math.abs(x)))
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
    netp = string.format("%+.0f%%", r.netp * 100), pu = pct(r.pu), cu = pct(r.cu),
    trend = r.trend and signed(r.trend) or "—",
  }
end

local function columns(details, width)
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
    if col.id=="item" then col.width=math.max(24,list_width(width)-total-#out*6) end
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
  if col.sub then return Loc.join(v[col.id], "\n[color=0.65,0.65,0.65]", v[col.sub], "[/color]") end
  return v[col.id]
end

local function grid(parent, name, cols)
  local t = parent.add { type = "table", name = name, style="ssk_balance_grid",
    column_count = #cols, draw_horizontal_lines=true, draw_vertical_lines=true }
  t.style.horizontal_spacing = 0
  t.style.left_cell_padding, t.style.right_cell_padding = 3, 3
  t.style.vertical_spacing = 0
  return t
end

-- The column header stays above the scroller, so it remains visible while the
-- rows scroll. It uses the same widths as the row tables beneath it.
local function make_header(parent, cols)
  local header = parent.add { type = "frame", name = "ssk_bal_header", style = "ssk_balance_header", direction = "vertical" }
  header.style.width = cols.list_width
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
  line.style.width = cols.list_width
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
      if col.id == "net" and r.net ~= 0 then
        el.style.font_color = r.net < 0 and { 1, 0.45, 0.4 } or { 1, 0.85, 0.35 }
      end
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
  header.style.left_padding,header.style.right_padding=6,8
  header.style.vertical_align="center"
  if star then star_button(header, star.set, star.tags, Loc("balance-this-group")) end
  local h=header.add{type="label",caption=caption,tooltip=caption,style="caption_label"}
  if star then h.style.left_margin=6 end
  h.style.width=width-14-(star and 30 or 0)
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
  for _, r in ipairs(rows) do
    local id = Groups.of(player.index, r.key)
    if not seen[id] then seen[id] = Groups.info(player.index, id); groups[#groups + 1] = seen[id] end
    by_key[r.key] = seen[id]
  end
  table.sort(groups, Groups.less)
  local function info(id)
    seen[id] = seen[id] or Groups.info(player.index, id)
    return seen[id]
  end
  local function group_of(key)
    by_key[key] = by_key[key] or info(Groups.of(player.index, key))
    return by_key[key]
  end
  -- A saved filter survives temporary inactivity; it can still be cleared.
  if us.bal_group and not seen[us.bal_group] then
    groups[#groups + 1] = info(us.bal_group)
    table.sort(groups, Groups.less)
  end
  local filtered = {}
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
  local order = not live_reuse and us.bal_sort or nil
  local display, normal, nfav, empty = arrange(favs, rows, filtered, by_key, info, order)
  local matching_count = nfav + #normal
  local limit = math.min(#normal, us.bal_limit or LIMIT)
  for i = 1, limit do
    local r = normal[i]
    display[#display + 1] = { row = r, section = us.bal_sort == "groups" and Loc.join("g:", by_key[r.key].id) or "all" }
  end
  if live_reuse then
    -- Keep click targets and open dropdowns alive. Explicit Refresh/filter actions
    -- reapply membership and ordering; live updates only change measured values.
    local current={}; for _,r in ipairs(rows) do current[r.key]=r end
    display={}
    for _,key in ipairs(previous.tags.visible_keys) do
      display[#display+1]={row=current[key] or {key=key,prod=0,cons=0,net=0,netp=0,status="ok",inactive=true}}
    end
  end
  local shown = #display
  local list = {}
  for i, d in ipairs(display) do list[i] = d.row end
  local signature = { tostring(us.bal_height), tostring(us.bal_width), tostring(us.bal_details), us.bal_sort or "priority", us.bal_filter or "problems", us.bal_group or "", tostring(shown), tostring(matching_count), tostring(#rows == 0) }
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

  -- Reuse existing cells while the visible rows stay the same. Live sampling
  -- updates values without destroying the table, dropdowns or scroll position.
  local same = live_reuse or (c.ssk_bal_root and c.ssk_bal_root.tags.signature == signature)
  local root, summaries, summary_heads, cells, refresh
  local cols = columns(us.bal_details, us.bal_width)
  local list_w = list_width(us.bal_width)
  cols.list_width = list_w
  if same then
    root = c.ssk_bal_root
    refresh = root.ssk_bal_controls.ssk_bal_refresh
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
    root = c.add { type = "flow", name = "ssk_bal_root", direction = "vertical", tags = { signature = signature, visible_keys=visible_keys } }
    root.style.vertical_spacing = 8
    local toolbar_width = (us.bal_width or 900) + 24
    root.style.width = toolbar_width
    root.style.height = us.bal_height or 600
    local toolbar = root.add { type = "flow", name = "ssk_bal_controls", direction = "horizontal" }
    local spacing = 4
    toolbar.style.vertical_align = "center"
    toolbar.style.horizontal_spacing = spacing
    toolbar.style.width = toolbar_width
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
    if not inline_details then
      details_row = root.add { type = "flow", direction = "horizontal" }
      details_row.style.width = toolbar_width
      details_row.style.vertical_align = "center"
      details_row.add { type = "empty-widget" }.style.horizontally_stretchable = true
    end
    details_row.add { type = "checkbox", caption = Loc("balance-details"), state = us.bal_details == true, tags = { ssk_ui = "bal_details" },
      tooltip = Loc("balance-show-net-percentage-producer-consumer-utilisation-and") }
    refresh = toolbar.add { type = "sprite-button", name = "ssk_bal_refresh", style = "tool_button", sprite = "utility/refresh",
      tags = { ssk_ui = "bal_update" }, tooltip = Loc("balance-refresh-table") }
    local summary = root.add { type = "table", name = "ssk_bal_summary", column_count = 3 }
    summary.style.horizontal_spacing = 8
    summary.vertical_centering = false
    local width = math.floor(((us.bal_width or 900) + 24 - 16) / 3)
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
    local list_flow = root.add { type = "frame", name = "ssk_bal_list", style = "inside_deep_frame", direction = "vertical" }
    list_flow.style.width = (us.bal_width or 900) + 24
    list_flow.style.padding = LIST_PADDING
    list_flow.style.vertically_stretchable = true
    if shown > 0 then make_header(list_flow, cols) end
    local items = list_flow.add { type = "scroll-pane", name = "ssk_bal_items", style = "naked_scroll_pane",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
    items.style.width = (us.bal_width or 900) + 24 - 2 * LIST_PADDING
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
        section.style.right_padding = LIST_GUTTER
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
        section.style.right_padding = LIST_GUTTER
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
        t = grid(section, "ssk_bal_table", cols)
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
    local net = list[i].net
    cells[i].net.style.font_color = net < 0 and { 1, 0.45, 0.4 } or net > 0 and { 1, 0.85, 0.35 } or { 1, 1, 1 }
    cells[i].focus.ssk_bal_inspect.toggled = us.bal_fx and us.bal_fx.focus == list[i].key or false
  end
  refresh.tooltip = Loc("balance-refresh-table")
  return list[1] and list[1].key
end

return BU
