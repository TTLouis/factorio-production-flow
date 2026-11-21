local Rail = require("scripts.cell_rail")
storage = {}
defines = { train_state = { wait_station = 1, no_path = 2, on_the_path = 3 }, inventory = { chest = 1 } }
local force, surface = { name = "player" }, { index = 1 }
local function entity(unit, kind)
  return { unit_number = unit, type = kind, valid = true, surface = surface, force = force }
end
local a, b, chest = entity(1, "train-stop"), entity(2, "train-stop"), entity(3, "container")
a.backer_name, b.backer_name = "Intake", "Intake"
chest.get_inventory = function()
  return { get_contents = function()
    return {{name = "iron-plate", quality = "normal", count = 9}, {name = "iron-plate", quality = "rare", count = 2}}
  end }
end
game = { tick = 0, forces = {player = force} }
local draft = { id = 4, surface_index = surface.index }
assert(Rail.select_stops(draft, {a,b}))
assert(Rail.select_buffers(draft, a.unit_number, {chest}))
assert(not Rail.select_buffers(draft, b.unit_number, {chest}), "A buffer may only belong to one physical stop")
assert(not Rail.conflict(draft.id, draft.stops))
local records = {[4] = {surface_index = 1, stops = draft.stops}}
Rail.reindex(records)
assert(Rail.conflict(5, draft.stops))
local stock, count, missing = Rail.stock(draft.stops[1], 1)
assert(count == 1 and missing == 0 and #stock == 2 and stock[2].quality == "rare")

local front = entity(9, "locomotive")
front.position = { x = 0, y = 0 }
local back = entity(10, "locomotive")
back.position = { x = 0, y = 7 }
local train = { id = 8, valid = true, station = a, speed = 0, state = 1, front_stock = front, back_stock = back }
local cargo = {
  {name = "iron-plate", quality = "normal", count = 17},
  {name = "iron-plate", quality = "rare", count = 2},
}
local water = 100
train.get_contents = function() return cargo end
train.get_fluid_contents = function() return {water = water} end
a.get_train_stop_trains = function() return {train} end
b.get_train_stop_trains = a.get_train_stop_trains
a.get_stopped_train = function() return train.station == a and train or nil end
b.get_stopped_train = function() return nil end
game.train_manager = { get_trains = function() return {train} end }

Rail.on_state { train = train, tick = 1, old_state = 3 }
assert(Rail.traffic(draft.stops, 1, force)[1].stopped == train)
cargo = { {name = "iron-plate", quality = "normal", count = 12}, {name = "iron-plate", quality = "rare", count = 3} }
water = 40
train.station, train.state = nil, 2
Rail.on_state { train = train, tick = 10, old_state = 1 }
Rail.on_tick(10)
assert(Rail.read_history(draft.stops, 0)[1].pending, "Losing the stop and path leaves the visit pending")
train.has_path, train.path_end_stop, train.state = true, b, 3
local scheduled_elsewhere = { id = 7, valid = true }
a.get_train_stop_trains = function() return {train, scheduled_elsewhere} end
b.get_train_stop_trains = a.get_train_stop_trains
local status = Rail.traffic(draft.stops, 1, force, 2)
assert(status[1].scheduled == status[2].scheduled and #status[1].headed == 0 and status[2].headed[1] == train)
assert(status[1].scheduled_trains == nil and #status[2].scheduled_trains == 2)
assert(status[2].scheduled_trains[1] == scheduled_elsewhere and status[2].scheduled_trains[2] == train)
train.speed, train.front_stock, train.back_stock, back.position = 0.1, back, front, {x = 3, y = 7}
Rail.on_tick(20)
local visits = Rail.read_history(draft.stops, 0)
assert(#visits == 1 and visits[1].stop == 1 and visits[1].tick == 20)
local up, down = Rail.summary(1, 0)
assert(#up == 1 and up[1].quality == "rare" and up[1].count == 1)
assert(#down == 2 and down[1].kind == "fluid" and down[1].count == 60 and down[2].count == 5)
train.station, train.state, train.speed = a, 1, 0
Rail.on_state { train = train, tick = 21, old_state = 3 }
Rail.on_train_created { old_train_id_1 = train.id }
assert(#Rail.read_history(draft.stops, 0) == 1, "Split and merge invalidates an incomplete visit")
Rail.reindex({})
assert(#Rail.read_history(draft.stops, 0) == 0, "Deleting or reassigning the linked stop clears its retained measurements")
local RailUI = require("scripts.cell_rail_ui")
local History = require("scripts.cell_rail_history")
local function count(kind, value)
  local result = History.material_count { kind = kind, count = value }
  if type(result) ~= "table" then return result end
  local suffix = ({ ["production-flow.rail-count-k"] = "K", ["production-flow.balance-m"] = "M",
    ["production-flow.history-g"] = "G" })[result[1]]
  assert(suffix, "Unexpected quantity suffix")
  return result[2] .. suffix
end
assert(count("fluid", 117180) == "117K" and count("item", 1200000) == "1.2M")
assert(count("item", 999) == "999" and count("fluid", 1000) == "1K")
assert(count("fluid", 999500) == "1M" and count("fluid", 999400) == "999K")
assert(count("fluid", 0.12345) == "0.12345" and count("item", 12) == "12")
local tree = {
  [10] = { id = 10, stops = {[1] = draft.stops[1]} },
  [11] = { id = 11, parent_id = 10, stops = {[2] = draft.stops[2]} },
  [12] = { id = 12, parent_id = 11, stops = {[3] = {}} },
  [13] = { id = 13, stops = {[4] = {}} },
}
local scoped, groups = RailUI.scope(tree, {10, 11, 13})
assert(scoped[1] and scoped[2] and scoped[3] and scoped[4] and #groups == 4,
  "Overlapping subtree roots must include each owned stop and group once")
scoped, groups = RailUI.scope(tree, {10, 13}, 11)
assert(not scoped[1] and scoped[2] and scoped[3] and not scoped[4] and #groups == 2,
  "Selected parent train scope must include only its own subtree")
storage.production_cells = { records = tree }
local state = { rail = {} }
assert(RailUI.on_click({ ssk_rail = "jump", cell = 12, unit = 3 }, state))
assert(state.selected == 12 and state.scope == 11 and #state.path == 2 and state.path[1] == 10
  and state.path[2] == 11 and state.rail.stop == 3, "Jump must select the actual owner in its sidebar scope")
-- Train limit reporting: finite limits are preserved, uint32 max (unlimited) is nil.
do
  local saved_tm = game.train_manager
  game.train_manager = { get_trains = function() return {} end }
  local function mk_stop(unit, limit, stopped)
    return {
      valid = true, unit_number = unit, type = "train-stop", surface = { index = 1 }, force = game.forces.player,
      backer_name = "S" .. unit, trains_limit = limit,
      get_train_stop_trains = function() return {} end,
      get_stopped_train = function() return stopped end,
    }
  end
  local s1 = mk_stop(901, 1, { id = 10 })
  local s2 = mk_stop(902, 4294967295, nil)
  local traffic = Rail.traffic({ [901] = { entity = s1, role = "import", buffers = {} },
    [902] = { entity = s2, role = "export", buffers = {} } }, 1, game.forces.player, 901)
  assert(traffic[901].limit == 1 and traffic[901].stopped.id == 10, "Finite trains_limit must be recorded")
  assert(traffic[902].limit == nil, "Unlimited uint32 max trains_limit must be nil")
  game.train_manager = saved_tm
end

print("CELL RAIL PASS: scoped stops, exclusive buffers, quality and fluid net cargo, physical departure, and split/merge")
