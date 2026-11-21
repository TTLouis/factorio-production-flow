local Suggestions = require('scripts.cell_rail_buffer_suggestions')
local force, surface = {}, {index = 1}
game, storage = {forces = {player = force}}, {}
defines = {inventory = {chest = 1}}
local function entity(id, kind)
  return {valid = true, unit_number = id, type = kind, force = force, surface = surface}
end
local stop, wagon, chest = entity(1, 'train-stop'), entity(2, 'cargo-wagon'), entity(3, 'container')
wagon.bounding_box = {left_top = {x = 10, y = 20}, right_bottom = {x = 12, y = 26}}
local train = {valid = true, carriages = {wagon}}
stop.get_stopped_train = function() return train end
local contents = {{name = 'iron-plate', count = 5}, {name = 'iron-plate', quality = 'rare', count = 1}}
chest.get_inventory = function() return {get_contents = function() return contents end} end
local inserter = entity(4, 'inserter')
inserter.pickup_target, inserter.drop_target = wagon, chest
surface.find_entities_filtered = function(filter)
  assert(filter.area and filter.area[1][1] == 2 and filter.area[1][2] == 12
    and filter.area[2][1] == 20 and filter.area[2][2] == 34, 'Search must be bounded around the wagon')
  return {inserter}
end
local draft = {surface_index = 1, stops = {[1] = {entity = stop, buffers = {}}}}
local materials = {['item/iron-plate'] = true}
local function match(claimed) return Suggestions.suggest(draft, 1, materials, claimed)[3] end
assert(match() == chest)
inserter.pickup_target, inserter.drop_target = chest, wagon
assert(match() == chest, 'Both loading and unloading are direct evidence')
assert(not match({[3] = true}), 'Staged owner blocks matching')
storage.cell_rail = {buffers = {[3] = 9}}
assert(not match(), 'Saved owner blocks matching')
storage.cell_rail.buffers = {}
draft.stops[9] = {buffers = {[3] = chest}}
assert(not match(), 'Another draft stop blocks matching')
draft.stops[9] = nil
contents[3] = {name = 'copper-plate', count = 1}
assert(not match(), 'Mixed material is ambiguous')
contents = {}
assert(not match(), 'Empty storage has no named material evidence')
chest.type, chest.prototype = 'logistic-container', {logistic_mode = 'storage'}
chest.storage_filter = {name = {name = 'iron-plate'}}
assert(match() == chest, 'An empty storage chest with an explicit matching filter is named')
chest.storage_filter = {name = {name = 'copper-plate'}}
assert(not match(), 'A different storage filter does not match')
chest.type = 'container'
contents = {{name = 'iron-plate', count = 1}}
inserter.drop_target = entity(5, 'cargo-wagon')
assert(not match(), 'A different wagon is not linked')
stop.get_stopped_train = function() return nil end
assert(not match(), 'No stopped train gives no evidence')

local ports = {[1] = materials}
local function selected(entities, sets, empty, id)
  return Suggestions.suggest_selected(draft, nil, entities, sets or ports, empty)[id or 1] or {}
end
assert(selected({chest})[3] == chest, 'Selected named chest matches one stop without a train')
local other = entity(6, 'train-stop')
other.get_stopped_train = function() return nil end
draft.stops[6] = {entity = other, buffers = {}}
assert(not selected({chest}, {[1] = materials, [6] = materials})[3], 'Shared material is ambiguous')
local tank = entity(7, 'storage-tank')
tank.get_fluid_contents = function() return {water = 50} end
local fluids = {[1] = {['fluid/water'] = true}}
assert(selected({tank}, fluids)[7] == tank, 'Single named fluid matches')
tank.get_fluid_contents = function() return {water = 5, ['crude-oil'] = 5} end
assert(not selected({tank}, fluids)[7], 'Mixed fluids are ambiguous')
contents = {}
assert(selected({chest}, ports, true)[3] == chest, 'Lone empty chest can be intentional')
assert(not selected({chest, tank}, ports, true)[3], 'Multiple buffers prevent empty pairing')
assert(not selected({chest}, fluids, true)[3], 'Empty chest cannot match fluid-only stop')
tank.get_fluid_contents = function() return {} end
assert(selected({tank}, fluids, true)[7] == tank, 'Lone empty tank can be intentional')
assert(not selected({tank}, ports, true)[7], 'Empty tank cannot match item-only stop')
contents = {{name = 'iron-plate', count = 1}}
stop.get_stopped_train = function() return train end
inserter.drop_target = wagon
assert(selected({chest}, {[1] = materials, [6] = materials})[3] == chest, 'Physical link resolves shared material')
assert(not selected({chest}, {[1] = materials, [6] = materials}, false, 6)[3], 'Physical owner wins regardless of order')
contents = {}
assert(selected({chest}, {[1] = materials, [6] = materials})[3] == chest, 'Explicitly selected empty chest has direct physical proof')
contents = {{name = 'iron-plate', count = 1}, {name = 'copper-plate', count = 1}}
assert(selected({chest}, {[1] = materials, [6] = materials})[3] == chest, 'Explicitly selected mixed chest has direct physical proof')
assert(not Suggestions.suggest(draft, 1, materials, nil)[3], 'Automatic inclusion still requires unambiguous named stock')
print('CELL RAIL BUFFER SUGGESTIONS PASS')
