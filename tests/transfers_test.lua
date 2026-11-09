local Transfers = require("scripts.transfers")
local player = { index = 1, valid = true }
local other = { index = 2, valid = true }
local nauvis = { index = 1, name = "nauvis", planet = { name = "nauvis" }, valid = true }
local freighter = { index = 2, name = "platform-1", valid = true, platform = { name = "Freighter", valid = true } }
local silo = { type = "rocket-silo", surface = nauvis, force = player, valid = true }
local hub = { type = "space-platform-hub", surface = freighter, force = player, valid = true }
local pad = { type = "cargo-landing-pad", surface = nauvis, force = player, valid = true }

defines = {
  inventory = { chest = 1, cargo_unit = 2 },
  cargo_destination = { invalid = 0, station = 1, surface = 2 },
  events = { on_cargo_pod_finished_ascending = 1, on_cargo_pod_finished_descending = 2,
    on_cargo_pod_delivered_cargo = 3 },
}
script = { active_mods = {} }
storage = {}
assert(not Transfers.available())
assert(Transfers.query(player, 1, 60).arrivals == 0)
script.active_mods["space-age"] = "2.1.24"
assert(Transfers.available())

local function inventory(...)
  local inv = { valid = true, ... }
  inv.is_empty = function() return #inv == 0 end
  return inv
end

local function stack(name, count, quality, spoil_tick)
  return { valid_for_read = true, name = name, count = count, quality = quality or "normal",
    spoil_tick = spoil_tick or 0 }
end

local next_pod = 1
local function depart(tick, origin, cargo, observed)
  local pod = { unit_number = next_pod, valid = true, name = "cargo-pod", cargo_pod_state = "ascending",
    surface = origin.surface, force = origin.force, cargo_pod_origin = origin, cargo = cargo }
  next_pod = next_pod + 1
  pod.get_inventory = function() return pod.cargo end
  if observed ~= false then Transfers.on_departed { tick = tick, cargo_pod = pod } end
  return pod
end

local function land(tick, pod, destination, station)
  pod.surface = destination
  pod.cargo_pod_state = "descending"
  pod.cargo_pod_destination = station and { type = defines.cargo_destination.station, station = station }
    or { type = defines.cargo_destination.surface, surface = destination }
  Transfers.on_landed { tick = tick, cargo_pod = pod }
end

local function deliver(tick, pod, contents)
  pod.cargo = inventory()
  pod.cargo_pod_destination = { type = defines.cargo_destination.invalid }
  local container
  if contents then
    container = { valid = true, force = pod.force, surface = pod.surface,
      get_inventory = function() return contents end }
  else
    pod.cargo_pod_state = "parking"
  end
  local event = { tick = tick, cargo_pod = pod, spawned_container = container }
  Transfers.on_delivered(event)
  Transfers.on_delivered(event)
end

local up = depart(10, silo, inventory(stack("iron-plate", 16), stack("iron-plate", 4, "uncommon"),
  stack("copper-plate", 9)))
land(100, up, freighter, hub)
-- Restore the module while retaining storage, as Factorio does on load.
package.loaded["scripts.transfers"] = nil
Transfers = require("scripts.transfers")
deliver(181, up)
local down = depart(190, hub, inventory(stack("iron-plate", 8)))
land(260, down, nauvis, pad)
deliver(341, down)
local ground = depart(350, hub, inventory(stack("fruit", 5, "normal", 440)))
land(420, ground, nauvis)
deliver(440, ground, inventory(stack("spoilage", 4)))

local spoiled = depart(441, silo, inventory(stack("fruit", 17, "normal", 580)))
land(500, spoiled, freighter, hub)
deliver(581, spoiled)
local destroyed = depart(582, hub, inventory(stack("steel-plate", 100)))
land(640, destroyed, nauvis, pad)
destroyed.valid = false
Transfers.on_housekeeping(650)
local ambiguous = depart(660, hub, inventory(stack("steel-plate", 100)))
land(700, ambiguous, nauvis, hub) -- Station is on a different surface.
deliver(781, ambiguous)
local cross_force = depart(790, hub, inventory(stack("steel-plate", 100)))
local enemy_pad = { type = pad.type, surface = pad.surface, force = other, valid = true }
land(860, cross_force, nauvis, enemy_pad)
deliver(941, cross_force)
local same_surface = depart(950, hub, inventory(stack("steel-plate", 100)))
land(1010, same_surface, freighter, hub)
deliver(1091, same_surface)
local old_save = depart(1100, hub, inventory(stack("steel-plate", 100)), false)
land(1200, old_save, nauvis, pad)
deliver(1281, old_save)

local total = Transfers.query(player, 1281, 60)
assert(total.routes == 2 and total.arrivals == 3 and total.items == 41 and #total.rows == 4)
assert(Transfers.query(other, 1281, 60).arrivals == 0)
assert(total.rows[1].count == 20 and total.rows[1].last == 181)
local source = total.rows[1].from.id
local destination = total.rows[1].to.id
assert(Transfers.query(player, 1281, 60, {from = source, to = destination, material = "iron-plate"}).items == 20)
assert(Transfers.query(player, 1281, 60, {from = destination}).items == 12)
assert(Transfers.query(player, 1281, 60, {material = "iron-plate"}).arrivals == 2)
assert(Transfers.query(player, 440, 1).items == 4)
assert(Transfers.query(player, 500, 1).items == 4)
assert(Transfers.query(player, 501, 1).items == 0)

freighter.platform.index, freighter.platform.surface = 23, freighter
player.platforms = { [17] = { valid = true, index = 17, name = "A waiting platform" }, [23] = freighter.platform }
prototypes = { item = { ["iron-plate"] = { weight = 1000 }, ["copper-plate"] = { weight = 500 },
  carbon = { weight = 100 } } }
local sampler = require("scripts.sampler")
local original_rates = sampler.rates
sampler.rates = function(index, period)
  assert(index == freighter.index and period == 10)
  return { nodes = { ["item/carbon"] = { prod = 1.5 }, ["fluid/water"] = { prod = 20 } } }, 6
end
storage.bins, game = {}, { forces = { player = player } }
local view = Transfers.platform_view(player, 601, 10, { platform = 23 })
assert(view.platforms[1].name == "A waiting platform" and view.platform.name == "Freighter")
assert(view.loaded.pods == 1 and view.loaded.weight == 24500 and not view.loaded.unknown_weight)
assert(view.unloaded.pods == 2 and view.unloaded.weight == 8000 and view.unloaded.unknown_weight)
assert(view.loading[1].endpoint.id == source and view.loading[1].items[1].name == "iron-plate")
assert(view.loading[1].items[1].count == 20 and view.loading[1].items[2].count == 9)
assert(view.materials.carbon and not view.materials.water and view.made.items[1].count == 9)
assert(view.made.weight == 900 and view.made.seconds == 6)
assert(view.arrival_count == 3 and view.arrivals[1].tick == 440 and view.arrivals[1].unknown_weight)
assert(view.arrivals[3].endpoint.id == source and view.arrivals[3].weight == 24500)

local no_load = Transfers.platform_view(player, 601, 10, { platform = 23, from = destination, view = "flow" })
assert(no_load.loaded.pods == 0 and no_load.unloaded.pods == 2 and #no_load.buckets == 0)
assert(no_load.sources[source] and no_load.destinations[source] and no_load.materials["copper-plate"])
local no_unload = Transfers.platform_view(player, 601, 10, { platform = 23, to = destination, view = "flow" })
assert(no_unload.loaded.pods == 1 and no_unload.unloaded.pods == 0)

local iron = Transfers.platform_view(player, 601, 10, { platform = 23, material = "iron-plate", view = "history" })
assert(iron.loaded.count == 20 and iron.unloaded.count == 8 and iron.unloaded.weight == 8000)
assert(iron.bucket_ticks == 60 and iron.arrival_count == 2 and #iron.loading == 0)
assert(iron.buckets[4].start_tick == 180 and iron.buckets[4].end_tick == 240)
assert(iron.buckets[4].loaded.count == 20 and iron.buckets[4].loaded.pods == 1)
assert(iron.buckets[4].loaded.items[2].name == "copper-plate" and iron.buckets[4].loaded.items[2].count == 9)
assert(iron.arrivals[2].items[2].name == "copper-plate" and iron.arrivals[2].weight == 24500)
local selected = Transfers.platform_view(player, 611, 10, { platform = 23, bucket = 180, view = "history" })
assert(selected.bucket == 180 and selected.arrival_count == 1 and selected.arrivals[1].id == iron.arrivals[2].id)
local idle = Transfers.platform_view(player, 611, 10, { view = "flow" })
assert(idle.platform.id == 17 and idle.loaded.pods == 0 and idle.made.seconds == 0)
assert(not Transfers.platform_view(other, 611, 10).platform)
game, storage.bins, sampler.rates = nil, nil, original_rates

freighter.platform.name = "Renamed Freighter"
assert(Transfers.describe(total.rows[1].to) == "Renamed Freighter")
assert(Transfers.platform_view(player, 1281, 60, { platform = 23 }).platform.name == "Renamed Freighter")
freighter.platform.valid = false
freighter.platform = nil
Transfers.on_surface_deleted { surface_index = freighter.index }
freighter.valid = false
assert(Transfers.describe(total.rows[1].to) == "Renamed Freighter")
local replacement = { index = 2, name = "platform-2", valid = true, platform = { name = "Freighter", valid = true } }
local new_hub = { type = hub.type, surface = replacement, force = player, valid = true }
local new_pod = depart(1300, silo, inventory(stack("iron-plate", 13)))
land(1400, new_pod, replacement, new_hub)
deliver(1481, new_pod)
total = Transfers.query(player, 1481, 60)
assert(total.routes == 3 and total.destinations[destination].surface == freighter)
assert(total.rows[2].to.id ~= destination and total.rows[2].to.surface == replacement)

-- Exercise ring wrap and retention with more completed arrivals than the limit.
storage = {}
for i = 1, 32769 do
  local tick = 1500 + i
  local pod = depart(tick, new_hub, inventory(stack("iron-plate", 1)))
  land(tick, pod, nauvis, pad)
  deliver(tick, pod)
end
total = Transfers.query(player, 34269, 600)
assert(total.truncated and total.arrivals == 32768 and total.items == 32768)
replacement.platform.index, replacement.platform.surface = 24, replacement
player.platforms[24] = replacement.platform
local wrapped = Transfers.platform_view(player, 34269, 600, { platform = 24, view = "history", page = 999 })
assert(wrapped.truncated and wrapped.unloaded.pods == 32768 and wrapped.unloaded.weight == 32768000)
assert(wrapped.arrival_count == 32768 and wrapped.page == 328 and wrapped.pages == 328)
assert(#wrapped.arrivals == 68 and wrapped.arrivals[#wrapped.arrivals].tick == 1502)
Transfers.on_housekeeping(34269 + 10 * 3600 * 60 + 1)
assert(storage.transfers.count == 0 and next(storage.transfers.dropped) == nil)

print("TRANSFERS OK: verified pod arrivals, loss guards, filters, retention, platform routes, weights, buckets and manifests")
