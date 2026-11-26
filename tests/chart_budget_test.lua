local Budget = TREQ("scripts.chart_budget")
local SK = TREQ("scripts.sankey_ui")
local UI = TREQ("scripts.ui")
local player = game.players[1]
local chart = { is_cell_chart = true, split_raw = false, chart_fit = true, show_labels = true }
local option = "ssk-bypass-sankey-size-limit"
local original_setting = settings.global[option]

local function fixture(input_count, output_count, rate, reverse)
  local graph = { nodes = {}, links = {}, columns = { "Inputs", "Outputs" }, mode = "measured", chart_zoom = true }
  for i = 1, input_count do
    local key = "item/iron-plate#" .. i
    graph.nodes[key] = { key = key, kind = "item", prod = 0, cons = output_count * rate, tier = 1, loops = {} }
  end
  for i = 1, output_count do
    local key = "item/copper-plate#" .. i
    graph.nodes[key] = { key = key, kind = "item", prod = input_count * rate, cons = 0, tier = 2, loops = {} }
  end
  for i = 1, input_count do
    local from = "item/iron-plate#" .. (reverse and input_count - i + 1 or i)
    for j = 1, output_count do
      local to = "item/copper-plate#" .. j
      graph.links[from .. ">" .. to] = { from = from, to = to, rate = rate, details = {} }
    end
  end
  return graph
end

local function count(map)
  local total = 0
  for _ in pairs(map) do total = total + 1 end
  return total
end

settings.global[option] = { value = false }
local selected = "item/copper-plate#155"
local first, second = fixture(3, 155, 2), fixture(3, 155, 2, true)
for _, graph in ipairs({ first, second }) do
  local size = Budget.apply(graph.nodes, graph.links, {}, { sel = selected }, {}, 0.001)
  assert(size.oversized and count(graph.nodes) == 150 and count(graph.links) <= 300)
  assert(graph.nodes[selected] and graph.links["item/iron-plate#1>" .. selected],
    "The selected material and its links should survive even when other links tie")
  for _, l in pairs(graph.links) do
    assert(graph.nodes[l.from] and graph.nodes[l.to] and l.rate == 2)
  end
end
for id in pairs(first.links) do assert(second.links[id], "Budget selection must be independent of insertion order") end
assert(count(second.links) == count(first.links))
local routes = {}
local small = fixture(1, 1, 2)
for i = 1, 305 do
  routes[i] = { sources = { small.nodes["item/copper-plate#1"] },
    targets = { { node = small.nodes["item/iron-plate#1"], rate = i } }, rate = i }
end
local size, visible = Budget.apply(small.nodes, small.links, routes, {}, {}, 0.001)
assert(size.oversized and count(small.links) + #visible == 300, "Return routes must count against the link budget")
assert(not Budget.reserve_copies({ nodes = 149 }, 2), "Raw-input copies must count against the node budget")

local holder = player.gui.screen.add { type = "frame", direction = "vertical" }
local function display(inputs, outputs, rate, automatic)
  SK.fill(player, holder, chart, 1000, 600, false, automatic, fixture(inputs, outputs, rate))
  return holder.ssk_sp.ssk_canvas
end
local canvas = display(1, 2, 1)
assert(not chart.oversized and not holder.ssk_size_notice.visible)
local child = canvas.children[1]
assert(display(1, 2, 1, true).children[1] == child, "An identical chart must keep its native elements")
assert(display(1, 2, 2, true).children[1] ~= child, "A change in displayed rates must redraw")
canvas = display(5, 100, 1)
assert(chart.oversized and holder.ssk_size_notice.visible
  and holder.ssk_size_notice.caption[1] == "production-flow.sankey-size-limited")
child = canvas.children[1]
assert(display(1, 2, 1, true).children[1] == child, "An oversized chart must wait for a manual refresh")
settings.global[option].value = true
display(3, 155, 1)
assert(holder.ssk_size_notice.caption[1] == "production-flow.sankey-size-unlimited"
  and holder.ssk_size_notice.tooltip[2] == 158 and holder.ssk_size_notice.tooltip[3] == 465,
  "The map setting must let manual rendering bypass both limits")
display(1, 2, 1)
assert(not chart.oversized and not holder.ssk_size_notice.visible, "A manual refresh must clear the warning for smaller graphs")
display(3, 155, 1, true)
assert(chart.oversized and holder.ssk_size_notice.caption[1] == "production-flow.sankey-size-limited",
  "Automatic updates must not render an uncapped chart that just grew over budget")
holder.destroy()
local Model = TREQ("scripts.model")
local build_model = Model.build
local model = { seconds = 60, edges = {}, residuals = {}, rates = { recipes = {} } }
for i = 1, 155 do
  local recipe = "recipe/budget-probe-" .. i
  for j = 1, 2 do
    model.edges[#model.edges + 1] = { from = "item/iron-plate#" .. j, to = recipe, rate = 1 }
  end
  model.edges[#model.edges + 1] = { from = recipe, to = "item/copper-plate#" .. i, rate = 2 }
end
Model.build = function() return model end
local full = player.gui.screen.add { type = "frame", direction = "vertical" }
local full_state = { view = "detail", split_raw = false }
settings.global[option].value = false
SK.fill(player, full, full_state, 1100, 600, true)
local function full_notice()
  local rows = full.ssk_bar.ssk_toolbar_strip.ssk_toolbar_rows
  local row = rows.ssk_toolbar_main
  local middle = row.ssk_toolbar_middle
  assert(#rows.children == 1 and not full.ssk_size_notice, "Full Sankey must not add a separate notice row")
  assert(row.children[middle.get_index_in_parent()-1].tags.ssk_sk == "preset"
    and middle.get_index_in_parent() < row.ssk_toolbar_actions.get_index_in_parent(),
    "The notice must appear between the dropdowns and actions")
  assert(SK.scroll_pane(full).style.height >= 582, "The notice must not take up chart height")
  return middle.ssk_size_notice
end
local full_status = full_notice()
assert(full_state.oversized and full_status.visible
  and full_status.caption[1] == "production-flow.sankey-size-limited")
assert(full_status.tooltip[2] <= 150 and full_status.tooltip[3] <= 300)
settings.global[option].value = true
SK.fill(player, full, full_state, 1100, 600, false)
full_status = full_notice()
assert(full_status.caption[1] == "production-flow.sankey-size-unlimited"
  and full_status.tooltip[2] == 157 and full_status.tooltip[3] == 310,
  "Full Sankey must respect the same manual override as Cells Flow")
Model.build = build_model
SK.fill(player, full, full_state, 1100, 600, false)
assert(not full_notice().visible, "The toolbar must clear the notice when the graph returns under budget")
full.destroy()
settings.global[option] = original_setting

local refresh, is_open, roster = UI.refresh, UI.is_open, game.connected_players
local refreshed = {}
UI.refresh = function(p, automatic)
  assert(automatic)
  refreshed[#refreshed + 1] = p.index
end
UI.is_open = function(p) return p.index ~= 3 end
game.connected_players = { { index = 1 }, { index = 2 }, { index = 3 } }
UI.auto_refresh(1, 50)
UI.auto_refresh(2, 50)
UI.auto_refresh(3, 50)
UI.auto_refresh(51, 50)
UI.refresh, UI.is_open, game.connected_players = refresh, is_open, roster
assert(table.concat(refreshed, ",") == "1,2,1", "Each player updates in a stable phase and closed windows are skipped")

print("CHART BUDGET PASS: retained selection, node and link limits, save bypass, refresh, and staggered players")
