-- Balance presentation only. The Sankey renderers continue to use view.lua.
local Balance = require("scripts.balance")
local Graph = require("scripts.graph")
local Groups = require("scripts.groups")

local BU = {}
BU.FILTERS = { "problems", "all", "shortages", "surpluses", "capacity" }
local FILTER_NAMES = { "Problems only", "Everything", "Supply/activity", "Surpluses", "Spare capacity" }
local SHORTAGE = { deficit = true, limited = true, starved = true }
local LIMIT = 200

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
  return r.status ~= "ok" and r.status ~= "source"
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
    help = "Stored items in provider/storage inventories on this surface, across all qualities, including robot pickup reservations. Other chests, requester inventories, items in transit and fluid tanks are excluded. — means no stock data; 0 means measured empty." },
  { id = "eta", name = "Empty in", width = 90, numeric = true,
    help = "Estimated time until logistic stock is empty if its current drain continues. Recent stock trend takes precedence over production minus consumption." },
  { id = "netp", name = "Net %", width = 70, numeric = true, detail = true,
    help = "Net rate divided by the larger of production and consumption. Differences within 5% count as balanced." },
  { id = "pu", name = "Producers", width = 90, numeric = true, detail = true,
    help = "Estimated producer utilisation: measured crafts / current crafting capacity. This is not a direct measurement of why a machine is idle." },
  { id = "cu", name = "Consumers", width = 90, numeric = true, detail = true,
    help = "Estimated consumer utilisation: measured crafts / current crafting capacity. Long periods use today's machines; values may exceed 100% after capacity changes." },
  { id = "trend", name = "Stock /min", width = 90, numeric = true, detail = true,
    help = "Recent change in logistic stock per minute (about 60 seconds), independent of the selected production averaging period." },
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
  local compact = { focus=24, status=146, prod=60, cons=60, net=62, stock=65, eta=66 }
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
    if col.id=="item" then col.width=math.max(24,width-total-(#out-1)*6-8) end
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

local function make_table(parent, cols)
  -- A band brackets related columns without spending any extra list width.
  local groups = {}
  for _,col in ipairs(cols) do
    local id = (col.id=="focus" or col.id=="item" or col.id=="status") and "item"
      or (col.id=="stock" or col.id=="eta") and "stock" or "rates"
    local g=groups[#groups]
    if not g or g.id~=id then g={id=id,width=0,count=0}; groups[#groups+1]=g end
    g.width=g.width+col.width+(g.count>0 and 6 or 0); g.count=g.count+1
  end
  local band=parent.add {type="table",name="ssk_bal_column_groups",style="ssk_balance_grid",
    column_count=#groups,draw_vertical_lines=true,draw_horizontal_line_after_headers=true}
  band.style.horizontal_spacing=0
  for _,g in ipairs(groups) do
    local title=g.id=="item" and "Item & status" or g.id=="stock" and "Logistic stock"
      or cols[1].details and "Rates & utilisation" or "Production rates"
    local heading=text(band,title)
    heading.style.width=g.width; heading.style.font="default-bold"
    heading.style.font_color={0.85,0.80,0.67}
    heading.style.horizontal_align="center"
  end
  local t = parent.add { type = "table", name = "ssk_bal_table", style="ssk_balance_grid",
    column_count = #cols, draw_horizontal_line_after_headers = true,
    draw_horizontal_lines=true, draw_vertical_lines=true }
  t.style.horizontal_spacing = 0
  t.style.left_cell_padding, t.style.right_cell_padding = 3, 3
  t.style.vertical_spacing = 0
  for _, col in ipairs(cols) do
    local l = text(t, col.name, col.help)
    l.style.font = "default-bold"
    l.style.width = col.width
    l.style.single_line = false
    l.style.horizontal_align = col.numeric and "right" or "left"
  end
  return t
end

local function add_row(parent, r, g, cols)
  local cells, v = {}, values(r)
  for _, col in ipairs(cols) do
    local el
    if col.id == "focus" then
      local spec = { type = "sprite-button", style = "tool_button", sprite = "utility/search",
        tooltip = "Show this item's materials and uses on the right", tags = { ssk_ui = "focus_item", key = r.key } }
      if not helpers.is_valid_sprite_path(spec.sprite) then spec.type = "button"; spec.sprite = nil; spec.caption = ">" end
      el = parent.add(spec)
      el.style.height = 24
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

function BU.fill(player, c, us, scope, only_auto)
  local rows, secs = Balance.rows(us.sidx, us.period)
  local groups, seen, by_key, counts = {}, {}, {}, {}
  for _, r in ipairs(rows) do
    local id = Groups.of(player.index, r.key)
    if not seen[id] then seen[id] = Groups.info(player.index, id); groups[#groups + 1] = seen[id] end
    by_key[r.key] = seen[id]
  end
  table.sort(groups, Groups.less)
  -- A saved filter survives temporary inactivity; it can still be cleared.
  if us.bal_group and not seen[us.bal_group] then
    local g = Groups.info(player.index, us.bal_group)
    groups[#groups + 1] = g
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
  local matching_count=#filtered
  local previous=c.ssk_bal_root
  local live_reuse=only_auto and previous and previous.tags.visible_keys
  if live_reuse then
    -- Keep click targets and open dropdowns alive. Explicit Refresh/filter actions
    -- reapply membership and ordering; live updates only change measured values.
    local current={}; for _,r in ipairs(rows) do current[r.key]=r end
    filtered={}
    for _,key in ipairs(previous.tags.visible_keys) do
      filtered[#filtered+1]=current[key] or {key=key,prod=0,cons=0,net=0,netp=0,status="ok",inactive=true}
    end
  end
  local shown = math.min(#filtered, us.bal_limit or LIMIT)
  local signature = { tostring(us.bal_height), tostring(us.bal_width), tostring(us.bal_details), us.bal_sort or "priority", us.bal_filter or "problems", us.bal_group or "", tostring(shown), tostring(#filtered), tostring(#rows == 0) }
  for _, g in ipairs(groups) do signature[#signature + 1] = g.id end
  for i = 1, shown do
    local r = filtered[i]
    signature[#signature + 1] = r.key .. ":" .. r.status .. ":" .. (by_key[r.key] and by_key[r.key].id or "")
  end
  signature = table.concat(signature, "|")

  -- Reuse existing cells while the visible rows stay the same. Live sampling
  -- updates values without destroying the table, dropdowns or scroll position.
  local same = live_reuse or (c.ssk_bal_root and c.ssk_bal_root.tags.signature == signature)
  local root, summaries, cells, context, counter
  if same then
    root = c.ssk_bal_root
    context, counter = root.ssk_bal_context, root.ssk_bal_footer.ssk_bal_count
    summaries, cells = {}, {}
    for _, id in ipairs({ "deficit", "limited", "starved", "surplus", "overbuilt", "ok", "source" }) do
      summaries[id] = root.ssk_bal_summary["ssk_bal_" .. id]
    end
    for i = 1, shown do
      local entry = root.ssk_bal_items["ssk_bal_section_" .. i]
      if entry then -- Sections are named for the first row they contain.
        local t = entry.ssk_bal_table
        local cols = columns(us.bal_details, us.bal_width)
        local offset = #cols
        local j = i
        while j <= shown and (j == i or not root.ssk_bal_items["ssk_bal_section_" .. j]) do
          cells[j] = {}
          for k, col in ipairs(cols) do cells[j][col.id] = t.children[offset + k] end
          offset = offset + #cols
          j = j + 1
        end
      end
    end
  else
    c.clear()
    local visible_keys={}; for i=1,shown do visible_keys[i]=filtered[i].key end
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
    picker.style.width = math.min(240, math.max(120, (us.bal_width or 900) - 290))
    toolbar = root.add { type = "flow", direction = "horizontal" }
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
    for _, id in ipairs({ "deficit", "limited", "starved", "surplus", "overbuilt", "ok", "source" }) do
      summaries[id] = summary.add { type = "label", name = "ssk_bal_" .. id, tooltip = Balance.STATUS[id].help }
      summaries[id].style.width = math.floor((us.bal_width or 900) / 2) - 18
      summaries[id].style.single_line = true
    end
    local hint = text(root, "Rates /s · stored logistic stock, all qualities · — unavailable · ≈ estimated empty time")
    hint.style.font="default-small"
    hint.style.font_color = { 0.65, 0.65, 0.65 }
    hint.style.single_line = false
    hint.style.maximal_width = us.bal_width or 900
    -- Only the item list scrolls; filters, summary and pagination stay visible.
    local items = root.add { type = "scroll-pane", name = "ssk_bal_items",
      horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
    items.style.width = (us.bal_width or 900) + 24
    items.style.horizontally_stretchable = true
    items.style.vertically_stretchable = true
    items.style.minimal_height = 0
    cells = {}
    local cols, t, last = columns(us.bal_details, us.bal_width), nil, nil
    for i = 1, shown do
      local r, g = filtered[i], by_key[filtered[i].key]
      if not t or (us.bal_sort == "groups" and last ~= g.id) then
        local section = items.add { type = "flow", name = "ssk_bal_section_" .. i, direction = "vertical" }
        if us.bal_sort == "groups" then
          local group_width=(us.bal_width or 900)-2
          section.style.vertical_spacing=0
          section.style.top_margin=i>1 and 14 or 0
          local header=section.add {type="frame",name="ssk_bal_group_header",
            style="repeated_subheader_frame",direction="horizontal"}
          header.style.width=group_width
          header.style.left_padding,header.style.right_padding=8,8
          local h=text(header,group_name(g),group_name(g))
          h.style.font="default-bold"
          h.style.font_color={0.95,0.85,0.65}
          h.style.width=group_width-16
          h.style.single_line=true
        end
        t = make_table(section, cols)
      end
      cells[i] = add_row(t, r, g, cols)
      if us.bal_sort=="groups" and (i==shown or by_key[filtered[i+1].key].id~=g.id) then
        local divider=t.parent.add {type="line",name="ssk_bal_group_end",direction="horizontal"}
        divider.style.width=(us.bal_width or 900)-2
      end
      last = g.id
    end
    if shown == 0 then
      text(items, #rows == 0 and "No measured production or consumption yet. Let the factory run, then refresh."
        or "No items match this view. Try Everything or All groups.")
    end
    local footer=root.add{type="flow",name="ssk_bal_footer",direction="horizontal"}
    footer.style.vertical_align="center"
    counter=footer.add{type="label",name="ssk_bal_count"}
    counter.style.width=math.max(100,(us.bal_width or 900)-120)
    counter.style.single_line=false
    local update=footer.add{type="button",caption="Update list",tags={ssk_ui="bal_update"},
      tooltip="Reapply filters and sorting, and include new items. Measured values keep updating while row order is held."}
    update.style.width=110
    if shown < #filtered then root.add { type = "button", caption = "Show 200 more", tags = { ssk_ui = "bal_more" } } end
  end
  context.caption = string.format("%s  ·  Averaged over %s  ·  Values update every 5 s", scope, time(secs))
  for id, el in pairs(summaries) do
    local st = Balance.STATUS[id]
    el.caption = string.format("[color=%s]%s: %d[/color]", st.color, st.label, counts[id] or 0)
  end
  for i = 1, shown do
    local v = values(filtered[i])
    for _,col in ipairs(columns(us.bal_details,us.bal_width)) do
      if col.id~="focus" then cells[i][col.id].caption=caption(v,col) end
    end
    if cells[i].status then
      cells[i].status.tooltip=filtered[i].inactive and "No measured activity in the current window. Update list to reapply filters and sorting."
        or Balance.STATUS[filtered[i].status].help
    end
    local net = filtered[i].net
    cells[i].net.style.font_color = net < 0 and { 1, 0.45, 0.4 } or net > 0 and { 1, 0.85, 0.35 } or { 1, 1, 1 }
    cells[i].focus.toggled = us.bal_fx and us.bal_fx.focus == filtered[i].key or false
  end
  counter.caption = live_reuse and string.format("List order held · %d rows · %d match now",shown,matching_count)
    or string.format("Showing %d of %d matching items", shown, #filtered)
  counter.tooltip="Live updates keep rows in place while updating values. Update list or change a filter to reapply row membership and ordering."
  return filtered[1] and filtered[1].key
end

return BU
