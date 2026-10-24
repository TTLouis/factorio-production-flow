-- Balance presentation only. The Sankey renderers continue to use view.lua.
local Balance = require("scripts.balance")
local Graph = require("scripts.graph")
local Groups = require("scripts.groups")

local Sampler = require("scripts.sampler")
local BU = {}
BU.FILTERS = { "problems", "all", "shortages", "surpluses", "capacity" }
local FILTER_NAMES = { "Problems only", "Everything", "Supply/activity", "Surpluses", "Spare capacity" }
local SHORTAGE = { deficit = true, limited = true, starved = true }
local LIMIT = 200
-- The item list pane is bal_width + 24 wide and always reserves its scrollbar,
-- so rows, group headers and the column header all fill the remaining width.
local SCROLLBAR = 12
local function list_width(width) return (width or 900) + 24 - SCROLLBAR end

-- Favourites stay at the top of the list whatever the filters; saved per player.
function BU.favourites(us)
  us.bal_favs = us.bal_favs or {}
  us.bal_favs.items = us.bal_favs.items or {}
  us.bal_favs.groups = us.bal_favs.groups or {}
  return us.bal_favs
end

local function text(parent, caption, tooltip)
  return parent.add { type = "label", caption = caption, tooltip = tooltip }
end

local function fmt(x)
  local a = math.abs(x)
  if a >= 1000000 then return string.format("%.2fM", x / 1000000) end
  if a >= 10000 then return string.format("%.1fk", x / 1000) end
  if a >= 100 then return string.format("%.0f", x) end
  if a >= 10 then return string.format("%.1f", x) end
  if a >= 1 then return string.format("%.2f", x) end
  if a > 0 and a < 0.001 then return "<0.001" end
  return string.format("%.3f", x)
end

local function signed(x)
  if x == 0 then return "0" end
  return (x > 0 and "+" or "−") .. fmt(math.abs(x))
end

local function time(sec)
  if not sec then return "—" end
  if sec >= 3600 then return string.format("%.1f h", sec / 3600) end
  if sec >= 60 then return string.format("%.0f min", sec / 60) end
  return string.format("%.0f s", sec)
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
  { id = "item", name = "Item / fluid", width = 220 },
  { id = "status", name = "Status", width = 145 },
  { id = "prod", name = "Produced", width = 80, numeric = true,
    help = "Measured production per second on the selected surface." },
  { id = "cons", name = "Consumed", width = 80, numeric = true,
    help = "Measured consumption per second on the selected surface." },
  { id = "net", name = "Net /s", width = 80, numeric = true,
    help = "Production minus consumption per second. Positive = surplus; negative = shortage." },
  { id = "stock", name = "Stock", width = 85, numeric = true,
    help = "Physical contents of ordinary and logistic chests on this surface, including requester and buffer chests, across all qualities. No logistic network is required. Belts, machines, vehicles, player inventories and fluid tanks are excluded. — means unavailable; 0 means measured empty." },
  { id = "eta", name = "Empty in", width = 90, numeric = true,
    help = "Estimated time until chest stock is empty if its current drain continues. Recent stock trend takes precedence over production minus consumption." },
  { id = "netp", name = "Net %", width = 70, numeric = true, detail = true,
    help = "Net rate divided by the larger of production and consumption. Differences within 5% count as balanced." },
  { id = "pu", name = "Producers", width = 90, numeric = true, detail = true,
    help = "Estimated producer utilisation: measured crafts / current crafting capacity. This is not a direct measurement of why a machine is idle." },
  { id = "cu", name = "Consumers", width = 90, numeric = true, detail = true,
    help = "Estimated consumer utilisation: measured crafts / current crafting capacity. Long periods use today's machines; values may exceed 100% after capacity changes." },
  { id = "trend", name = "Stock /min", width = 90, numeric = true, detail = true,
    help = "Recent change in chest stock per minute (seven samples: about 30 minutes, longer for large scans), independent of the selected production averaging period." },
}

local function values(r)
  local st = Balance.STATUS[r.status]
  return {
    item = item_name(r.key), status = r.inactive and "[color=0.65,0.65,0.65]Inactive[/color]" or string.format("[color=%s]%s[/color]", st.color, st.label),
    prod = fmt(r.prod), cons = fmt(r.cons), net = signed(r.net),
    stock = r.stock and fmt(r.stock) or "—", eta = r.eta and "≈ "..time(r.eta) or "—",
    netp = string.format("%+.0f%%", r.netp * 100), pu = pct(r.pu), cu = pct(r.cu),
    trend = r.trend and signed(r.trend) or "—",
  }
end

local function columns(details, width)
  local out = {}
  width = width or 900
  local compact = { focus=52, status=146, prod=60, cons=60, net=62, stock=65, eta=66 }
  local detail = { prod="pu", cons="cu", net="netp", stock="trend" }
  local subhead = { prod="Util. %", cons="Util. %", net="Net %", stock="/min" }
  local total = 0
  for _, col in ipairs(COLUMNS) do
    if not col.detail and not (col.id=="status" and width<680)
      and not ((col.id=="stock" or col.id=="eta") and width<550) then
      local copy = {}
      for k,v in pairs(col) do copy[k]=v end
      copy.width = compact[col.id] or 0
      if width<550 and col.numeric then copy.width=52 end
      if col.id=="prod" then copy.name="Made /s" end
      if col.id=="cons" then copy.name="Used /s" end
      if details and detail[col.id] then
        copy.sub=detail[col.id]
        copy.name=copy.name.."\n"..subhead[col.id]
        for _,extra in ipairs(COLUMNS) do
          if extra.id==copy.sub then copy.help=copy.help.."\n\n"..extra.help end
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
      out[#out+1]="\nStock: "..v.stock.." · Empty: "..v.eta
      if col.details then out[#out+1]="\nStock /min: "..v.trend end
    end
    return out
  end
  if col.sub then return v[col.id].."\n[color=0.65,0.65,0.65]"..v[col.sub].."[/color]" end
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
  local header = parent.add { type = "flow", name = "ssk_bal_header", direction = "vertical" }
  header.style.vertical_spacing = 0
  -- A band brackets related columns without spending any extra list width.
  local groups = {}
  for _,col in ipairs(cols) do
    local id = (col.id=="focus" or col.id=="item" or col.id=="status") and "item"
      or (col.id=="stock" or col.id=="eta") and "stock" or "rates"
    local g=groups[#groups]
    if not g or g.id~=id then g={id=id,width=0,count=0}; groups[#groups+1]=g end
    g.width=g.width+col.width+(g.count>0 and 6 or 0); g.count=g.count+1
  end
  local band=header.add {type="table",name="ssk_bal_column_groups",style="ssk_balance_grid",
    column_count=#groups,draw_vertical_lines=true}
  band.style.horizontal_spacing=0
  for _,g in ipairs(groups) do
    local title=g.id=="item" and "Item & status" or g.id=="stock" and "Chest stock"
      or cols[1].details and "Rates & utilisation" or "Production rates"
    local heading=band.add{type="label",caption=title,style="caption_label"}
    heading.style.width=g.width
    heading.style.horizontal_align="center"
  end
  local t = grid(header, "ssk_bal_columns", cols)
  for _, col in ipairs(cols) do
    local l = text(t, col.name, col.help)
    l.style.font = "default-bold"
    l.style.font_color = { 0.9, 0.9, 0.9 }
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
    tooltip = set and "Remove " .. what .. " from favourites"
      or "Add " .. what .. " to favourites: always listed at the top, whatever the filters" }
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
      star_button(el, fav, { ssk_ui = "bal_fav", key = r.key }, "this item")
      local spec = { type = "sprite-button", name = "ssk_bal_inspect", style = "tool_button", sprite = "utility/search",
        tooltip = "Show this item's materials and uses on the right", tags = { ssk_ui = "focus_item", key = r.key } }
      if not helpers.is_valid_sprite_path(spec.sprite) then spec.type = "button"; spec.sprite = nil; spec.caption = ">" end
      local inspect = el.add(spec)
      inspect.style.width, inspect.style.height = 24, 24
    else
      local tooltip = col.id == "item" and { "", item_name(r.key), "\n", group_name(g), "\n", r.key }
        or col.id == "status" and Balance.STATUS[r.status].help or col.help
      el = text(parent, caption(v,col), tooltip)
      el.style.horizontal_align = col.numeric and "right" or "left"
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
  if star then star_button(header, star.set, star.tags, "this group") end
  local h=header.add{type="label",caption=caption,tooltip=caption,style="caption_label"}
  if star then h.style.left_margin=6 end
  h.style.width=width-14-(star and 30 or 0)
  h.style.single_line=true
  return header
end

-- Display order: favourite items, favourite groups (whole), then the filtered
-- list. Favourites ignore Show / Group and do not count towards the row limit.
local function arrange(us, rows, filtered, by_key, info)
  local favs = BU.favourites(us)
  local display, used = {}, {}
  local function push(r, section)
    used[r.key] = true
    display[#display + 1] = { row = r, section = section }
  end
  local present = {}
  for _, r in ipairs(rows) do present[r.key] = r end
  local missing = {}
  for _, r in ipairs(rows) do if favs.items[r.key] then push(r, "fav") end end
  for key in pairs(favs.items) do if not present[key] then missing[#missing + 1] = key end end
  table.sort(missing)
  for _, key in ipairs(missing) do
    push({ key = key, prod = 0, cons = 0, net = 0, netp = 0, status = "ok", inactive = true }, "fav")
  end
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
    for _, r in ipairs(members) do push(r, "fg:" .. g.id) end
    if #members == 0 then empty[#empty + 1] = { group = g, before = #display + 1 } end
  end
  local nfav = #display
  local normal = {}
  for _, r in ipairs(filtered) do
    if not used[r.key] and not favs.groups[by_key[r.key].id] then normal[#normal + 1] = r end
  end
  return display, normal, nfav, empty
end

function BU.fill(player, c, us, scope, only_auto)
  local rows, secs = Balance.rows(us.sidx, us.period)
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
  local favs = BU.favourites(us)
  local display, normal, nfav, empty = arrange(us, rows, filtered, by_key, info)
  local matching_count = nfav + #normal
  local limit = math.min(#normal, us.bal_limit or LIMIT)
  for i = 1, limit do
    local r = normal[i]
    display[#display + 1] = { row = r, section = us.bal_sort == "groups" and "g:" .. by_key[r.key].id or "all" }
  end
  local previous=c.ssk_bal_root
  local live_reuse=only_auto and previous and previous.tags.visible_keys
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
  for key in pairs(favs.items) do fav_keys[#fav_keys + 1] = "*" .. key end
  for gid in pairs(favs.groups) do fav_keys[#fav_keys + 1] = "#" .. gid end
  table.sort(fav_keys)
  for _, k in ipairs(fav_keys) do signature[#signature + 1] = k end
  for _, e in ipairs(empty) do signature[#signature + 1] = "empty:" .. e.group.id end
  for i = 1, shown do
    local r = list[i]
    signature[#signature + 1] = r.key .. ":" .. r.status .. ":" .. (display[i].section or "")
  end
  signature = table.concat(signature, "|")

  -- Reuse existing cells while the visible rows stay the same. Live sampling
  -- updates values without destroying the table, dropdowns or scroll position.
  local same = live_reuse or (c.ssk_bal_root and c.ssk_bal_root.tags.signature == signature)
  local root, summaries, cells, context, counter
  local cols = columns(us.bal_details, us.bal_width)
  local list_w = list_width(us.bal_width)
  cols.list_width = list_w
  if same then
    root = c.ssk_bal_root
    context, counter = root.ssk_bal_context, root.ssk_bal_footer.ssk_bal_count
    summaries, cells = {}, {}
    for _, id in ipairs({ "deficit", "limited", "starved", "surplus", "overbuilt", "ok", "source", "stored" }) do
      summaries[id] = root.ssk_bal_summary["ssk_bal_" .. id]
    end
    for i = 1, shown do
      local entry = root.ssk_bal_list.ssk_bal_items["ssk_bal_section_" .. i]
      if entry then -- Sections are named for the first row they contain.
        local t = entry.ssk_bal_table
        -- Reading children copies the whole array through the Factorio API.
        -- Cache it once, not once for every cell in the table.
        local children = t.children
        local offset = 0
        local j = i
        while j <= shown and (j == i or not root.ssk_bal_list.ssk_bal_items["ssk_bal_section_" .. j]) do
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
    root.style.width = (us.bal_width or 900) + 24
    root.style.height = us.bal_height or 600
    local toolbar = root.add { type = "flow", direction = "horizontal" }
    toolbar.style.vertical_align = "center"
    toolbar.style.horizontal_spacing = 8
    text(toolbar, "Show:")
    local fi = 1
    for i, id in ipairs(BU.FILTERS) do if id == us.bal_filter then fi = i end end
    local filter = toolbar.add { type = "drop-down", items = FILTER_NAMES, selected_index = fi, tags = { ssk_ui = "bal_filter" } }
    filter.style.width = 145
    text(toolbar, "Group:")
    local names, gi = { "All groups" }, 1
    us.bal_group_ids = {}
    for i, g in ipairs(groups) do
      names[i + 1] = group_name(g); us.bal_group_ids[i + 1] = g.id
      if g.id == us.bal_group then gi = i + 1 end
    end
    local picker = toolbar.add { type = "drop-down", items = names, selected_index = gi, tags = { ssk_ui = "bal_group" } }
    picker.style.width = math.min(240, math.max(120, (us.bal_width or 900) - 322))
    if us.bal_group then
      star_button(toolbar, favs.groups[us.bal_group], { ssk_ui = "bal_fav_group", gid = us.bal_group }, "this group")
    end
    toolbar = root.add { type = "flow", direction = "horizontal" }
    toolbar.style.vertical_align = "center"
    toolbar.style.horizontal_spacing = 8
    text(toolbar, "Order:")
    toolbar.add { type = "drop-down", items = { "Priority", "Item groups" }, selected_index = us.bal_sort == "groups" and 2 or 1,
      tags = { ssk_ui = "bal_sort" } }
    toolbar.add { type = "checkbox", caption = "Details", state = us.bal_details == true, tags = { ssk_ui = "bal_details" },
      tooltip = "Show net percentage, producer / consumer utilisation and recent stock trend." }
    context = root.add { type = "label", name = "ssk_bal_context" }
    context.style.single_line = false
    context.style.maximal_width = us.bal_width or 900
    local summary = root.add { type = "table", name = "ssk_bal_summary", column_count = 2 }
    summary.style.horizontal_spacing = 18
    summaries = {}
    for _, id in ipairs({ "deficit", "limited", "starved", "surplus", "overbuilt", "ok", "source", "stored" }) do
      summaries[id] = summary.add { type = "label", name = "ssk_bal_" .. id, tooltip = Balance.STATUS[id].help }
      summaries[id].style.width = math.floor((us.bal_width or 900) / 2) - 18
      summaries[id].style.single_line = true
    end
    local hint = text(root, "Rates /s · chest stock, all qualities · — unavailable · ≈ estimated empty time · ★ keeps a row or group at the top")
    hint.style.font="default-small"
    hint.style.font_color = { 0.65, 0.65, 0.65 }
    hint.style.single_line = false
    hint.style.maximal_width = us.bal_width or 900
    -- Only the item list scrolls; filters, summary, column header and pagination
    -- stay visible. The scroller has no border, so rows use the whole pane.
    local list_flow = root.add { type = "flow", name = "ssk_bal_list", direction = "vertical" }
    list_flow.style.vertical_spacing = 0
    list_flow.style.vertically_stretchable = true
    if shown > 0 then make_header(list_flow, cols) end
    local items = list_flow.add { type = "scroll-pane", name = "ssk_bal_items", style = "naked_scroll_pane",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
    items.style.width = (us.bal_width or 900) + 24
    items.style.vertically_stretchable = true
    items.style.minimal_height = 0
    cells = {}
    local t, last
    local e = 1
    local function empty_groups(before)
      while empty[e] and empty[e].before <= before do
        local g = empty[e].group
        local section = items.add { type = "flow", name = "ssk_bal_empty_" .. e, direction = "vertical" }
        section.style.vertical_spacing = 0
        section.style.top_margin = #items.children > 1 and 8 or 0
        section_header(section, list_w, group_name(g), { set = true, tags = { ssk_ui = "bal_fav_group", gid = g.id } })
        local note = text(section, "No items in this group right now.")
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
        local section = items.add { type = "flow", name = "ssk_bal_section_" .. i, direction = "vertical" }
        section.style.vertical_spacing = 0
        section.style.top_margin = #items.children > 1 and 8 or 0
        if d.section == "fav" then
          section_header(section, list_w, "[img=ssk-star] Favourites")
        elseif d.section:sub(1, 3) == "fg:" then
          section_header(section, list_w, group_name(g), { set = true, tags = { ssk_ui = "bal_fav_group", gid = g.id } })
        elseif d.section:sub(1, 2) == "g:" then
          section_header(section, list_w, group_name(g), { set = false, tags = { ssk_ui = "bal_fav_group", gid = g.id } })
        elseif nfav > 0 or #empty > 0 then
          section_header(section, list_w, "All other items")
        end
        t = grid(section, "ssk_bal_table", cols)
      end
      cells[i] = add_row(t, r, g, cols, favs.items[r.key] == true)
      last = d.section
    end
    empty_groups(math.huge)
    if #normal == 0 then
      local note = text(items, #rows == 0 and "No measured activity or chest stock yet. Let sampling finish, then Update list."
        or "No items match this view. Try Everything or All groups.")
      if shown > 0 then note.style.top_margin = 8 end
    end
    local footer=root.add{type="flow",name="ssk_bal_footer",direction="horizontal"}
    footer.style.vertical_align="center"
    counter=footer.add{type="label",name="ssk_bal_count"}
    counter.style.width=math.max(100,(us.bal_width or 900)-120)
    counter.style.single_line=false
    local update=footer.add{type="button",caption="Update list",tags={ssk_ui="bal_update"},
      tooltip="Reapply filters and sorting, and include new items. Measured values keep updating while row order is held."}
    update.style.width=110
    if limit < #normal then root.add { type = "button", caption = "Show 200 more", tags = { ssk_ui = "bal_more" } } end
  end
  local stock_status=Sampler.stock_status()
  local age=stock_status.updated_tick and time(math.max(0,game.tick-stock_status.updated_tick)/60).." ago" or "first scan pending"
  context.caption = string.format("%s · Averaged over %s · Rates update every 5 s\nChest stock: %s · At least 5 min between scans", scope, time(secs),age)
  for id, el in pairs(summaries) do
    local st = Balance.STATUS[id]
    el.caption = string.format("[color=%s]%s: %d[/color]", st.color, st.label, counts[id] or 0)
  end
  for i = 1, shown do
    local v = values(list[i])
    for _,col in ipairs(cols) do
      if col.id~="focus" then cells[i][col.id].caption=caption(v,col) end
    end
    if cells[i].status then
      cells[i].status.tooltip=list[i].inactive and "No measured activity in the current window. Update list to reapply filters and sorting."
        or Balance.STATUS[list[i].status].help
    end
    local net = list[i].net
    cells[i].net.style.font_color = net < 0 and { 1, 0.45, 0.4 } or net > 0 and { 1, 0.85, 0.35 } or { 1, 1, 1 }
    cells[i].focus.ssk_bal_inspect.toggled = us.bal_fx and us.bal_fx.focus == list[i].key or false
  end
  counter.caption = live_reuse and string.format("List order held · %d rows · %d match now",shown,matching_count)
    or string.format("Showing %d of %d matching items", shown, matching_count)
      .. (nfav > 0 and string.format(" · %d favourite%s", nfav, nfav == 1 and "" or "s") or "")
  counter.tooltip="Automatic updates keep rows in place while updating values. Update list or change a filter to reapply row membership and ordering."
  return list[1] and list[1].key
end

return BU
