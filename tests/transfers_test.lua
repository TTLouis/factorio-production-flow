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
    on_cargo_pod_delivered_cargo = 3,on_space_platform_changed_state=4 },
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

-- Dispatch and receipt are separate evidence, with independent times and
-- qualities. Losing or expiring a pending pod must not erase its dispatch.
local boundaries = Transfers.boundaries(player, nauvis, 1281, 60)
local origin, arrival, lost
for _, record in ipairs(boundaries.records) do
  if record.kind == "sent" and record.tick == 10 then origin = record end
  if record.kind == "received" and record.tick == 341 then arrival = record end
  if record.kind == "sent" and record.tick == 582 then lost = record end
end
assert(origin and origin.items["iron-plate"] == 20 and origin.to.surface == freighter)
assert(origin.contents[2].quality == "normal" and origin.contents[2].count == 16)
assert(origin.contents[3].quality == "uncommon" and origin.contents[3].count == 4)
assert(arrival and arrival.items["iron-plate"] == 8 and lost and lost.items["steel-plate"] == 100)
assert(Transfers.boundaries(other, nauvis, 1281, 60).records[1] == nil)
assert(#Transfers.boundaries(player, nauvis, 1281, 60, {kind="received",material="iron-plate"}).records == 2)
origin.items["iron-plate"], origin.contents[2].count = -1, -1
for _, record in ipairs(Transfers.boundaries(player, nauvis, 1281, 60).records) do
  if record.kind == "sent" and record.tick == 10 then assert(record.items["iron-plate"] == 20 and record.contents[2].count == 16) end
end
assert(#Transfers.boundaries(player, freighter, 50, 60).records == 0,
  "a destination discovered by a later landing must not leak into an earlier query")

freighter.platform.index, freighter.platform.surface = 23, freighter
player.platforms = { [17] = { valid = true, index = 17, name = "A waiting platform" }, [23] = freighter.platform }
prototypes = { item = { ["iron-plate"] = { weight = 1000 }, ["copper-plate"] = { weight = 500 },
  carbon = { weight = 100 } } }
local sampler = require("scripts.sampler")
local original_rates = sampler.rates
sampler.rates = function(index, period)
  assert(index == freighter.index)
  return { nodes = { ["item/iron-plate"] = { prod = 2 }, ["item/copper-plate"] = { prod = 1 },
    ["item/carbon"] = { prod = 1.5 }, ["fluid/water"] = { prod = 20 } } }, math.min(6, period)
end
storage.bins, game = {}, { forces = { player = player } }
local view = Transfers.platform_view(player, 601, 10, { platform = 23 })
assert(view.platforms[1].name == "A waiting platform" and view.platform.name == "Freighter")
assert(view.loaded.pods == 1 and view.loaded.weight == 24500 and not view.loaded.unknown_weight)
assert(view.unloaded.pods == 2 and view.unloaded.weight == 8000 and view.unloaded.unknown_weight)
assert(view.loading[1].endpoint.id == source and view.loading[1].items[1].name == "iron-plate")
assert(view.loading[1].items[1].count == 20 and view.loading[1].items[2].count == 9)
assert(not view.materials.carbon and not view.materials.water)
assert(#view.made.items == 1 and view.made.items[1].name == "iron-plate" and view.made.items[1].count == 12)
assert(view.made.weight == 12000 and view.made.seconds == 6)
assert(view.arrival_count == 3 and view.arrivals[1].tick == 440 and view.arrivals[1].unknown_weight)
assert(view.arrivals[3].endpoint.id == source and view.arrivals[3].weight == 24500)

local all = Transfers.platform_view(player, 601, 10, { platform = 23, show_all_production = true })
assert(#all.made.items == 3 and all.made.weight == 15900 and all.materials.carbon)
assert(all.loaded.weight == view.loaded.weight and all.unloaded.weight == view.unloaded.weight)
assert(all.arrival_count == view.arrival_count and all.arrivals[1].id == view.arrivals[1].id)
local recent = Transfers.platform_view(player, 601, 3, { platform = 23, view = "flow" })
assert(recent.unloaded.pods == 1 and #recent.made.items == 0)
local copper = Transfers.platform_view(player, 601, 10, { platform = 23, material = "copper-plate", view = "flow" })
assert(copper.loaded.count == 9 and copper.unloaded.pods == 0 and #copper.made.items == 0)

local no_load = Transfers.platform_view(player, 601, 10, { platform = 23, from = destination, view = "flow" })
assert(no_load.loaded.pods == 0 and no_load.unloaded.pods == 2 and #no_load.buckets == 0)
assert(no_load.sources[source] and no_load.destinations[source] and no_load.materials["copper-plate"])
local no_unload = Transfers.platform_view(player, 601, 10, { platform = 23, to = destination, view = "flow" })
assert(no_unload.loaded.pods == 1 and no_unload.unloaded.pods == 0 and #no_unload.made.items == 0)

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
local replacement_events = Transfers.boundaries(player, replacement, 1481, 60)
assert(#replacement_events.records == 2 and replacement_events.records[1].items["iron-plate"] == 13,
  "a reused surface index must not expose the archived surface's boundary events")

-- A silo relinquishes its attached cargo at launch order, before the rocket's
-- ascent animation finishes. Snapshot that valid association once, preserving
-- the original qualities independently of a later receipt inventory.
storage = {}
local ordered = depart(2000,silo,inventory(stack("iron-plate",11),stack("iron-plate",7,"rare")),false)
ordered.cargo_pod_state="awaiting_launch"
local rocket={valid=true,attached_cargo_pod=ordered}
local unrelated_silo={valid=true,type="rocket-silo",surface=nauvis,force=player}
Transfers.on_rocket_launch_ordered{tick=2000,rocket=rocket,rocket_silo=unrelated_silo}
assert(not storage.transfers,"an attached pod from another silo cannot establish a dispatch")
Transfers.on_rocket_launch_ordered{tick=2000,rocket={valid=false,attached_cargo_pod=ordered},rocket_silo=silo}
assert(not storage.transfers,"an invalid rocket cannot establish a dispatch")
Transfers.on_rocket_launch_ordered{tick=2000,rocket=rocket,rocket_silo=silo}
local launch_records=Transfers.boundaries(player,nauvis,2000,60,{kind="sent"}).records
assert(#launch_records==1 and launch_records[1].tick==2000 and launch_records[1].items["iron-plate"]==18)
assert(launch_records[1].contents[1].quality=="normal" and launch_records[1].contents[1].count==11)
assert(launch_records[1].contents[2].quality=="rare" and launch_records[1].contents[2].count==7)
assert(Transfers.query(player,2000,60).arrivals==0,"dispatch observation must not alter confirmed-arrival history")
ordered.cargo_pod_state="ascending"
Transfers.on_departed{tick=2100,cargo_pod=ordered}
assert(storage.transfers.boundary_observations.count==1,"finished ascent must not duplicate an ordered launch")
ordered.cargo=inventory(stack("iron-plate",5))
land(2200,ordered,replacement,new_hub);deliver(2300,ordered)
launch_records=Transfers.boundaries(player,nauvis,2300,60).records
assert(#launch_records==2 and launch_records[1].kind=="received" and launch_records[1].items["iron-plate"]==5)
assert(launch_records[2].kind=="sent" and launch_records[2].tick==2000 and launch_records[2].contents[2].count==7,
  "arrival changes cannot replace the exact original origin manifest")

-- A witnessed delivery with unmeasurable cargo is a received-coverage gap,
-- never a zero receipt or a copy of the sent manifest. Replayed successful
-- callbacks must not introduce gaps after their pending entries are removed.
storage = {}
Transfers.on_housekeeping(0)
local known_receipt=depart(10,new_hub,inventory(stack("iron-plate",10)))
land(20,known_receipt,nauvis,pad);deliver(30,known_receipt)
local known_coverage=Transfers.boundaries(player,nauvis,30,0.5)
assert(not known_coverage.received_partial and known_coverage.coverage.received==0.5,
  "a duplicate confirmed delivery must not create missing-receipt coverage")
local unknown_receipt=depart(40,new_hub,inventory(stack("fruit",17,"normal",50)))
land(45,unknown_receipt,nauvis,pad);deliver(60,unknown_receipt)
local incomplete=Transfers.boundaries(player,nauvis,600,10)
assert(incomplete.coverage.sent==10 and incomplete.coverage.received==9 and incomplete.received_partial
  and incomplete.received_gap_tick==60 and not incomplete.truncated,
  "unmeasurable receipts must reduce only received coverage at their real timestamp")
assert(#Transfers.boundaries(player,nauvis,600,10,{kind="received"}).records==1,
  "unknown cargo must not become a zero or inferred receipt manifest")
assert(not Transfers.boundaries(player,replacement,600,10).received_partial
  and not Transfers.boundaries(other,nauvis,600,10).received_partial,
  "receipt gaps must preserve surface and force identity")
assert(not Transfers.boundaries(player,nauvis,600,8).received_partial,
  "a window after the unknown delivery can regain complete received coverage")
assert(not Transfers.boundaries(player,nauvis,50,50/60).received_partial,
  "future receipt uncertainty must not leak into earlier queries")

-- Public stop/movement observations identify visits, not arbitrary time buckets.
storage={}
freighter.valid=true
local platform={valid=true,index=77,name="Visit probe",force=player,surface=freighter,space_location={name="nauvis"}}
freighter.platform=platform;player.platforms={[77]=platform}
Transfers.on_platform_changed_state{platform=platform,tick=100}
silo.unit_number,silo.name,silo.position=20011,"rocket-silo",{x=0,y=0}
hub.unit_number,hub.name,hub.position=20012,"space-platform-hub",{x=2,y=0}
pad.unit_number,pad.name,pad.position=20013,"cargo-landing-pad",{x=4,y=0}
local visit_up=depart(110,silo,inventory(stack("iron-plate",20)))
land(120,visit_up,freighter,hub);deliver(130,visit_up)
local before_landing=Transfers.boundaries(player,nauvis,119,10).records
assert(#before_landing==1 and before_landing[1].sender.unit_number==20011 and before_landing[1].receiver==nil,
  "Future destination identities leaked into an earlier boundary query")
local entity_copy=Transfers.boundaries(player,nauvis,130,10).records
assert(entity_copy[1].receiver.unit_number==20012 and entity_copy[1].sender.unit_number==20011)
entity_copy[1].sender.position.x=999
assert(Transfers.boundaries(player,nauvis,130,10).records[1].sender.position.x==0,"Endpoint query mutated the stored identity")
local visit_down=depart(140,hub,inventory(stack("iron-plate",30)))
land(150,visit_down,nauvis,pad);deliver(160,visit_down)
local exchange=Transfers.platform_view(player,200,10,{platform=77,view="history",axis="events"})
assert(#exchange.exchanges==1 and exchange.exchanges[1].loaded.pods==1 and exchange.exchanges[1].unloaded.pods==1,
  "A stop with both directions must be one cargo exchange")
local visit_key=exchange.exchanges[1].key
assert(Transfers.platform_view(player,200,10,{platform=77,view="history",exchange=visit_key}).arrival_count==2)
package.loaded["scripts.transfers"]=nil;Transfers=require("scripts.transfers")
Transfers.on_platform_changed_state{platform=platform,tick=210}
assert(storage.transfers.platform_visits[77].id==storage.transfers.history[1].exchange_id,"Reload/state change split the same visit")
platform.space_location=nil;Transfers.on_platform_changed_state{platform=platform,tick=220}
platform.space_location={name="nauvis"};Transfers.on_platform_changed_state{platform=platform,tick=230}
-- This empty return visit is not an exchange.
assert(#Transfers.platform_view(player,240,10,{platform=77,view="history",axis="events"}).exchanges==1)
local second=depart(250,hub,inventory(stack("iron-plate",5)))
land(260,second,nauvis,pad);deliver(270,second)
exchange=Transfers.platform_view(player,300,10,{platform=77,view="history",axis="events"})
assert(#exchange.exchanges==2 and exchange.exchanges[2].key~=visit_key,"Repeated visit merged with an earlier exchange")
local selected=Transfers.platform_view(player,300,10,{platform=77,view="history",exchange=visit_key})
assert(selected.arrival_count==2 and #selected.arrivals==2,"Exchange click did not retain both directions in its log")
freighter.platform={name="Freighter",valid=true}
freighter.valid=false

-- Exercise ring wrap and retention with more completed arrivals than the limit.
storage = {}
for i = 1, 4096 do depart(1500+i,new_hub,inventory(stack("iron-plate",1))) end
local over_capacity=depart(6000,new_hub,inventory(stack("iron-plate",7)))
assert(storage.transfers.pending_count==4096 and not storage.transfers.pending[over_capacity.unit_number])
local count_before_finish=storage.transfers.boundary_observations.count
Transfers.on_departed{tick=6500,cargo_pod=over_capacity}
assert(storage.transfers.boundary_observations.count==count_before_finish,
  "start and finish events must not duplicate a dispatch when pending capacity is full")
local excess=0
for _,record in ipairs(Transfers.boundaries(player,replacement,6500,600,{kind="sent"}).records) do
  if record.pod_id==over_capacity.unit_number then excess=excess+1;assert(record.items["iron-plate"]==7 and record.tick==6000) end
end
assert(excess==1,"the dispatch survives even when no pending slot was available")
land(6510,over_capacity,nauvis,pad);deliver(6520,over_capacity)
local cap_coverage=Transfers.boundaries(player,nauvis,6600,10)
assert(cap_coverage.received_partial and cap_coverage.received_gap_tick==6520
  and cap_coverage.coverage.received<cap_coverage.coverage.sent,
  "a real delivery omitted by the pending cap must disclose incomplete receipts")
assert(#Transfers.boundaries(player,nauvis,6600,10,{kind="received"}).records==0,
  "pending overflow must not invent a received amount from its known dispatch")
storage = {}
local evicted_dispatch_pod=depart(1499,new_hub,inventory(stack("copper-plate",5)))
assert(#Transfers.boundaries(player,replacement,1499,1,{companions=true}).records==1)
for i = 1, 32769 do
  local tick = 1500 + i
  local pod = depart(tick, new_hub, inventory(stack("iron-plate", 1)))
  land(tick, pod, nauvis, pad)
  deliver(tick, pod)
end
total = Transfers.query(player, 34269, 600)
assert(total.truncated and total.arrivals == 32768 and total.items == 32768)
local limited = Transfers.boundaries(player, nauvis, 34269, 600)
assert(limited.truncated and #limited.records == 32768,
  "the independent dispatch/receipt ledger is bounded, even after ring wrap")
replacement.platform.index, replacement.platform.surface = 24, replacement
player.platforms[24] = replacement.platform
local wrapped = Transfers.platform_view(player, 34269, 600, { platform = 24, view = "history", page = 999 })
assert(wrapped.truncated and wrapped.unloaded.pods == 32768 and wrapped.unloaded.weight == 32768000)
assert(wrapped.arrival_count == 32768 and wrapped.page == 328 and wrapped.pages == 328)
assert(#wrapped.arrivals == 68 and wrapped.arrivals[#wrapped.arrivals].tick == 1502)
local later = 34269 + 50 * 3600 * 60 + 1
local long = Transfers.platform_view(player, later, 250 * 3600, { platform = 24, view = "history" })
assert(long.truncated and long.arrival_count == 32768 and #long.buckets <= 16)
assert(long.covered_seconds < 250 * 3600 and long.covered_seconds > 50 * 3600)
assert(Transfers.platform_view(player, later, 50 * 3600, { platform = 24, view = "history" }).arrival_count == 0)
-- The query index was built before ring wrap. An old dispatch evicted by the
-- cap must not reappear when its still-pending pod finally delivers.
land(34400,evicted_dispatch_pod,nauvis,pad);deliver(34401,evicted_dispatch_pod)
local evicted_pair=Transfers.boundaries(player,nauvis,34401,1,{companions=true}).records
assert(#evicted_pair==1 and evicted_pair[1].kind=="received",
  "Derived shipment index resurrected an evicted dispatch")
Transfers.on_housekeeping(34401 + 1000 * 3600 * 60 + 1)
assert(storage.transfers.count == 0 and next(storage.transfers.dropped) == nil)
assert(storage.transfers.boundary_observations.count == 0 and next(storage.transfers.boundary_observations.dropped) == nil)
assert(next(storage.transfers.boundary_observations.sent_by_pod)==nil,
  "retention removes duplicate guards along with their dispatch records")

print("TRANSFERS OK: verified pod arrivals, loss guards, filters, retention, platform routes, weights, buckets and manifests")
