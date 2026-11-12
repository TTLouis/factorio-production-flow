
local B = TREQ("scripts.balance")
local rows = B.rows(nil)
for _, r in ipairs(rows) do
  print(string.format("BAL %-10s %-34s prod %7.3f cons %7.3f net %+.0f%% pu %s cu %s stock %s trend %s eta %s",
    r.status, r.key, r.prod, r.cons, r.netp * 100, r.pu and string.format("%.2f", r.pu) or "-", r.cu and string.format("%.2f", r.cu) or "-",
    tostring(r.stock), r.trend and string.format("%.0f", r.trend) or "-", r.eta and string.format("%.0f", r.eta) or "-"))
end
local UI = TREQ("scripts.ui")
storage.ui[1].tab_id = "balance"; storage.ui[1].bal_filter = "all"; UI.refresh(game.players[1])
UI.on_selection({ element = { valid = true, tags = { ssk_ui = "bal_filter" }, selected_index = 1 }, player_index = 1 })
local BU = TREQ("scripts.balance_ui")
local player, us = game.players[1], storage.ui[1]
local function content() return player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_balance end
local function root() return content().ssk_balance_split.ssk_balance_table.ssk_bal_root end
local function find(el, pred, out)
  out = out or {}
  if pred(el) then out[#out + 1] = el end
  for _, child in ipairs(el.children) do find(child, pred, out) end
  return out
end
local function select(action, index)
  assert(UI.on_selection({ player_index = 1, element = { tags = { ssk_ui = action }, selected_index = index } }))
end
local function tables() return find(root(), function(e) return e.name == "ssk_bal_table" end) end
local function links() return find(root(), function(e) return e.tags.ssk_ui == "focus_item" end) end
assert(tables()[1].column_count == 8, "compact summary should have 8 columns including focus")
local original = root()
local item_pane = original.ssk_bal_list.ssk_bal_items
assert(content().ssk_balance_split.ssk_balance_table.type == "flow", "outer Balance pane must stay fixed")
assert(item_pane.type == "scroll-pane", "only the item list should scroll")
assert(original.ssk_bal_summary and not original.ssk_bal_context and original.ssk_bal_controls.ssk_bal_refresh
  and not original.ssk_bal_footer, "refresh must be in the header and the footer must be absent")
assert(item_pane.ssk_bal_section_1, "item tables must live inside the scroller")
local function check_header_alignment()
  local list=root().ssk_bal_list
  local header=list.ssk_bal_header
  assert(not header.ssk_bal_column_groups, "Balance must not have a second band of headings")
  local columns=header.ssk_bal_columns
  for _,t in ipairs(tables()) do
    assert(t.column_count==columns.column_count, "Header and rows have different columns")
    for i,h in ipairs(columns.children) do
      assert(h.style.width==t.children[i].style.width, "Header width differs from data column "..i)
    end
    assert(t.parent.style.right_padding>=8, "Empty in needs breathing room before the scrollbar")
  end
end
check_header_alignment()

UI.refresh(player, true)
assert(root() == original and root().ssk_bal_list.ssk_bal_items == item_pane, "unchanged live refresh must preserve the item scroller")
select("bal_filter", 3)
for _, e in ipairs(links()) do
  local status
  for _, r in ipairs(B.rows(1, us.period)) do if r.key == e.tags.key then status = r.status end end
  assert(status == "deficit" or status == "limited" or status == "starved", "shortage filter leaked another status")
end
assert(#links() > 0, "shortages should be visible")
select("bal_filter", 4)
for _, e in ipairs(links()) do
  local status
  for _, r in ipairs(B.rows(1, us.period)) do if r.key == e.tags.key then status = r.status end end
  assert(status == "surplus", "surplus filter leaked another status")
end
select("bal_filter", 2)
select("bal_sort", 2)
assert(#tables() > 1, "group ordering should show separate group sections")
local grouped = root()
UI.refresh(player, true)
assert(root() == grouped, "grouped live update should reuse every section")
assert(UI.on_checked({ player_index = 1, element = { tags = { ssk_ui = "bal_details" }, state = true } }))
for _, t in ipairs(tables()) do assert(t.column_count == 8, "details must stack without adding width")
  assert(LOC(t.children[4].caption):find("\n"), "producer utilisation should appear beneath production") end
check_header_alignment()
local group_index
for i, id in pairs(us.bal_group_ids) do if id == "plates" then group_index = i end end
assert(group_index, "active curated group missing")
select("bal_group", group_index)
for _, e in ipairs(links()) do assert(TREQ("scripts.groups").of(1, e.tags.key) == "plates", "group filter leaked an item") end
assert(#links() > 0)
select("bal_group", 1)

-- Favourites stay at the top whatever the filters, and toggle off again.
local function click(tags) UI.on_click({ player_index = 1, element = { valid = true, name = "x", tags = tags } }) end
local function keys() local out = {}; for i, e in ipairs(links()) do out[i] = e.tags.key end; return out end
local hidden
for _, r in ipairs(B.rows(1, us.period)) do
  if not BU.matches(r, "problems") and TREQ("scripts.groups").of(1, r.key) ~= "plates" then hidden = r.key; break end
end
assert(hidden, "fixture needs a row outside Problems only")
select("bal_filter", 1); select("bal_sort", 1)
for _, k in ipairs(keys()) do assert(k ~= hidden, "chosen row should be filtered out before it is a favourite") end
click({ ssk_ui = "bal_fav", key = hidden })
assert(us.bal_favs.items[hidden] and keys()[1] == hidden, "favourite item must lead the list despite the filter")
local pane = root().ssk_bal_list.ssk_bal_items
assert(pane.ssk_bal_section_1.ssk_bal_group_header and pane.ssk_bal_section_2.ssk_bal_group_header, "favourites and other items need headers")
assert(not root().ssk_bal_footer, "favourites must not restore the removed footer")
for _, e in ipairs(find(root(), function(e) return e.tags.ssk_ui == "bal_fav" and e.tags.key == hidden end)) do
  assert(e.sprite == "ssk-star", "favourite star should be filled")
end
click({ ssk_ui = "bal_fav_group", gid = "plates" })
local plates = {}
for _, r in ipairs(B.rows(1, us.period)) do
  if TREQ("scripts.groups").of(1, r.key) == "plates" then plates[r.key] = true end
end
local listed = keys()
assert(listed[1] == hidden, "favourite items come before favourite groups")
local n = 0
for k in pairs(plates) do n = n + 1; assert(plates[listed[n + 1]], "whole favourite group must follow the favourite items") end
assert(n > 0)
select("bal_filter", 4)
assert(keys()[1] == hidden and plates[keys()[2]], "favourites ignore the Show filter")
click({ ssk_ui = "bal_fav", key = hidden }); click({ ssk_ui = "bal_fav_group", gid = "plates" })
assert(not next(us.bal_favs.items) and not next(us.bal_favs.groups), "stars must toggle off")
assert(not root().ssk_bal_list.ssk_bal_items.ssk_bal_section_1.ssk_bal_group_header, "priority order without favourites has no section header")
select("bal_filter", 2)

-- Deterministic fixture verifies pagination, real caption updates, zero stock,
-- missing stock, localisation, and status-driven table invalidation.
local saved_rows = B.rows
local fixture = {}
for i = 1, 205 do
  fixture[i] = { key = "item/test-" .. i, prod = 2, cons = 1, net = 1, netp = 0.5,
    status = "surplus", stock = i == 1 and 0 or nil }
end
local old_proto = rawget(prototypes.item, "test-1")
prototypes.item["test-1"] = { name = "test-1", subgroup = { name = "x" }, localised_name = { "item-name.test-1" } }
B.rows = function() return fixture, 60 end
us.bal_group, us.bal_sort, us.bal_details, us.bal_limit = nil, "priority", false, nil
UI.refresh(player)
assert(#links() == 200 and #find(root(), function(e) return e.tags.ssk_ui == "bal_more" end) > 0, "pagination must offer the remaining items")
UI.on_click({ player_index = 1, element = { name = "x", tags = { ssk_ui = "bal_more" } } })
assert(#links() == 205, "show more must expose all remaining rows")
local t = tables()[1]
assert(LOC(t.children[7].caption) == "0.000", "known zero stock must not become missing stock")
assert(LOC(t.children[15].caption) == "—", "missing stock must stay unavailable")
assert(t.children[2].caption[4] == prototypes.item["test-1"].localised_name, "use prototype display name")
local summary = root().ssk_bal_summary
assert(summary.column_count == 3 and summary.ssk_bal_under and summary.ssk_bal_ok and summary.ssk_bal_over, "activity summary must have three themed columns")
assert(LOC(summary.ssk_bal_over.ssk_bal_theme.caption):find("Overproducing: 205", 1, true), "summary must count the full filtered set, not just the first page")
local reuse = root()
fixture[1].prod = 3
UI.refresh(player, true)
assert(root() == reuse and LOC(t.children[4].caption) == "3.00", "live numbers must update in place")
fixture[1].status = "deficit"
UI.refresh(player, true)
assert(root()==reuse and LOC(t.children[3].caption):find("Deficit"), "live status changes must update cells without destroying controls")
assert(LOC(summary.ssk_bal_under.ssk_bal_theme.caption):find("Underproducing: 1", 1, true)
  and LOC(summary.ssk_bal_over.ssk_bal_theme.caption):find("Overproducing: 204", 1, true), "theme totals must update without rebuilding the list")
local original_first=t.children[1]
table.remove(fixture,1)
UI.refresh(player,true)
assert(root()==reuse and t.children[1]==original_first and LOC(t.children[3].caption):find("Inactive"), "expired rows must not interrupt selection")
UI.refresh(player)
assert(root()~=reuse, "manual Refresh must reapply list membership")
fixture = {}
UI.refresh(player)
assert(#links() == 0 and not root().ssk_bal_footer, "empty data state")

-- Sort equal measurements in their original priority order. Explicit refresh
-- reorders the table, while a live refresh keeps the same scrolled targets.
local function sort_row(name, net, eta, status)
  return { key = "item/" .. name, prod = 100 + net, cons = 100, net = net, netp = net / 100,
    eta = eta, status = status }
end
local relative = sort_row("relative", -6, 30, "deficit")
local tied_first = sort_row("tied-z", -10, 30, "deficit")
local tied_second = sort_row("tied-a", -10, nil, "deficit")
local biggest = sort_row("biggest", -100, 120, "ok")
biggest.prod, biggest.cons, biggest.netp = 2400, 2500, -0.04
local surplus = sort_row("surplus", 30, 15, "surplus")
local steady = sort_row("steady", 0, nil, "ok")
fixture = { relative, tied_first, tied_second, surplus, biggest, steady }
local function expect_order(...)
  local expected, actual = { ... }, keys()
  assert(#actual == #expected, "wrong number of sorted rows")
  for i, row in ipairs(expected) do
    assert(actual[i] == row.key, "row " .. i .. " should be " .. row.key .. ", got " .. actual[i])
  end
end
select("bal_sort", 1)
expect_order(relative, tied_first, tied_second, surplus, biggest, steady)
select("bal_sort", 3)
assert(us.bal_sort == "deficit")
expect_order(biggest, tied_first, tied_second, relative, surplus, steady)
select("bal_sort", 4)
assert(us.bal_sort == "empty")
local sort_picker = find(root(), function(e) return e.tags.ssk_ui == "bal_sort" end)[1]
assert(LOC(sort_picker.items[3]) == "Biggest deficit" and LOC(sort_picker.items[4]) == "Soonest empty"
  and sort_picker.selected_index == 4, "Order dropdown labels and selection must agree")
expect_order(surplus, relative, tied_first, biggest, tied_second, steady)
local sorted = root()
local sorted_pane = sorted.ssk_bal_list.ssk_bal_items
biggest.eta, surplus.eta = 5, nil
UI.refresh(player, true)
assert(root() == sorted and sorted.ssk_bal_list.ssk_bal_items == sorted_pane)
expect_order(surplus, relative, tied_first, biggest, tied_second, steady)
click(sorted.ssk_bal_controls.ssk_bal_refresh.tags)
expect_order(biggest, relative, tied_first, tied_second, surplus, steady)
click({ ssk_ui = "bal_fav", key = surplus.key })
select("bal_sort", 3)
expect_order(surplus, biggest, tied_first, tied_second, relative, steady)
check_header_alignment()

-- A watch can warn or recover as measurements change without changing the
-- row list, item width, or scroller. Its evaluation sees the existing sample.
local Watch = TREQ("scripts.watch")
local saved_evaluate = Watch.evaluate
local stock, totals = {}, {}
B.rows = function() return fixture, 60, stock, true, totals end
local watch_calls, warning = 0, nil
Watch.evaluate = function(p, state, seconds, raw_stock, known, raw_totals)
  assert(p == player and state == us and seconds == 60)
  assert(raw_stock == stock and known and raw_totals == totals)
  watch_calls = watch_calls + 1
  return { [surplus.key] = warning }
end
local function check_watch_row()
  local watched = root()
  local watched_cell = assert(find(watched, function(e)
    return e.tags.ssk_ui == "bal_material" and e.tags.key == surplus.key
  end)[1])
  local calls = watch_calls
  warning = "Watched stock is low."
  UI.refresh(player, true)
  assert(watch_calls == calls + 1 and root() == watched, "one watch evaluation per Balance update")
  assert(watched_cell.caption[2] == "[img=utility/warning_icon] " and watched_cell.tooltip[4] == warning,
    "the existing item cell must show its watch warning")
  warning = nil
  UI.refresh(player, true)
  assert(watch_calls == calls + 2 and root() == watched and watched_cell.valid)
  assert(watched_cell.caption[2] ~= "[img=utility/warning_icon] " and watched_cell.tooltip[6] == surplus.key,
    "watch recovery must clear the icon and restore the item tooltip")
end
check_watch_row()
click({ ssk_ui = "bal_fav", key = surplus.key })
local watched_group = TREQ("scripts.groups").of(player.index, surplus.key)
click({ ssk_ui = "bal_fav_group", gid = watched_group })
assert(not us.bal_favs.items[surplus.key] and us.bal_favs.groups[watched_group])
check_watch_row()
click({ ssk_ui = "bal_fav_group", gid = watched_group })
Watch.evaluate = saved_evaluate

B.rows = saved_rows
prototypes.item["test-1"] = old_proto
us.bal_details, us.bal_filter, us.bal_limit, us.bal_sort = false, "problems", nil, "priority"
UI.refresh(player)
print("BAL UI OK")
