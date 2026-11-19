local F=require("scripts.transport_flows")
local T=require("scripts.transfers")
local force={index=1,valid=true,platforms={}}
local other={index=2,valid=true}
local local_surface={index=1,name="Nauvis",valid=true}
local remote_surface={index=2,name="Orbit",valid=true}
defines={events={on_cargo_pod_finished_ascending=1,on_cargo_pod_finished_descending=2,on_cargo_pod_delivered_cargo=3},
  inventory={cargo_unit=1,chest=2},cargo_destination={station=1,surface=2}}
script={active_mods={}}
game={tick=1200,forces={player=force}}
storage={}
prototypes={item={['iron-plate']={},['copper-plate']={},['water-barrel']={}}}
local function near(a,b)assert(a and math.abs(a-b)<1e-9,tostring(a).." ~= "..tostring(b))end
local function endpoint(surface,id)return{surface=surface,id=id,name=surface.name}end
local function stack(name,count,quality)return{name=name,count=count,quality=quality or "normal"}end
assert(F.query(force,local_surface,1200,10).provider==nil)
assert(not next(F.query({index=1,valid=false},local_surface,1200,10).materials))
assert(not next(F.query(force,local_surface,1200,-1).materials))
assert(not next(F.query(force,local_surface,0/0,10).materials))

-- Real SA event handlers retain distinct origin and destination inventories.
script.active_mods={['space-age']='2.1.24'};storage={}
local function inventory(items)
  local inv={valid=true}
  for _,item in ipairs(items)do inv[#inv+1]={valid_for_read=true,name=item.name,count=item.count,
    quality=item.quality,spoil_tick=0}end
  inv.is_empty=function()return #inv==0 end
  return inv
end
local silo={valid=true,type='rocket-silo',surface=local_surface,force=force}
local hub={valid=true,type='space-platform-hub',surface=remote_surface,force=force}
local function depart(id,tick,origin,items)
  local pod={valid=true,name='cargo-pod',unit_number=id,cargo_pod_state='ascending',surface=origin.surface,
    force=force,cargo_pod_origin=origin,cargo=inventory(items)}
  pod.get_inventory=function()return pod.cargo end
  T.on_departed{cargo_pod=pod,tick=tick};return pod
end
local function deliver(pod,tick,destination,items)
  pod.surface=destination.surface;pod.cargo_pod_state='descending'
  pod.cargo_pod_destination={type=defines.cargo_destination.station,station=destination}
  pod.cargo=inventory(items)
  T.on_landed{cargo_pod=pod,tick=tick-1}
  pod.cargo=inventory({});pod.cargo_pod_state='parking'
  T.on_delivered{cargo_pod=pod,tick=tick}
end
T.on_housekeeping(0)
local up=depart(1,700,silo,{stack('iron-plate',20),stack('iron-plate',4,'rare')})
deliver(up,800,hub,{stack('iron-plate',18),stack('iron-plate',2,'rare')})
local lost=depart(2,900,silo,{stack('copper-plate',7)})
lost.valid=false;T.on_housekeeping(1000)
local q=F.query(force,local_surface,1200,10)
assert(q.provider=='sa' and q.coverage_known)
local iron=q.materials['item/iron-plate']
near(iron.exports.sent,24);near(iron.exports.received,20)
assert(iron.exports.routes[1].method=='cargo-pod' and iron.exports.routes[1].remote_name=='Orbit',
  'SA hover route metadata lost the remote surface or transport method')
assert(not iron.exports.sent_partial and not iron.exports.received_partial)
near(q.materials['item/copper-plate'].exports.sent,7)
assert(q.materials['item/copper-plate'].exports.received==nil)
near(F.query(force,remote_surface,1200,10).materials['item/iron-plate'].imports.received,20)
local events=F.events(force,local_surface,1200,10,{material='item/iron-plate'})
assert(#events==2 and events[1].stats_included==false)
script.active_mods["space-age"]="2.1.25"
assert(F.events(force,local_surface,1200,10)[1].stats_included==nil,
  "A version without audited statistics semantics cannot inherit the exclusion flag")
script.active_mods["space-age"]="2.1.24"
near(events[1].delta+events[2].delta,-24)
local h=F.history(force,remote_surface,1200,7,{material='iron-plate'})
assert(#h.records==1 and h.records[1].tick==700 and h.records[1].arrival_tick==800)
near(h.records[1].sent[1].count,20)
assert(F.query(other,local_surface,1200,10).materials['item/iron-plate']==nil)
-- An old receipt remains exact all-quality evidence, not a fabricated dispatch
-- or a claim that its unknown quality was normal.
storage.transfers.history[storage.transfers.count+1]={force=force,from=endpoint(remote_surface,2),
  to=endpoint(local_surface,1),tick=1100,items={['water-barrel']=9}}
storage.transfers.count=storage.transfers.count+1
q=F.query(force,local_surface,1200,10)
local barrels=q.materials['item/water-barrel']
near(barrels.imports.received,9);assert(barrels.imports.sent==nil)
h=F.history(force,local_surface,1200,10,{material='water-barrel'})
assert(#h.records==1 and h.records[1].sent==nil and h.records[1].received[1].quality==nil)
assert(#F.history(force,local_surface,1200,10,{material='water-barrel',quality='normal'}).records==0)
events=F.events(force,local_surface,1200,10,{material='water-barrel'})
assert(#events==1 and events[1].delta==9 and events[1].quality==nil and not events[1].quality_exact)
depart(3,1150,silo,{stack('copper-plate',3)})
T.on_housekeeping(40000)
assert(storage.transfers.pending_count==0)
near(F.query(force,local_surface,40000,1000).materials['item/copper-plate'].exports.sent,10)
-- A real delivery with no measurable payload does not reduce dispatch coverage
-- or become a fabricated receipt. Its coverage gap remains independent.
local old_boundaries=T.boundaries
local receipt_gap,receipt_seconds=600,10
T.boundaries=function()
  return {coverage_known=true,covered_seconds=20,coverage={sent=20,received=receipt_seconds},
    received_gap_tick=receipt_gap,received_partial=receipt_gap~=nil,records={
      {shipment_id=99,kind='sent',tick=1000,from=endpoint(remote_surface,2),to=endpoint(local_surface,1),
        contents={stack('iron-plate',20)}},
      {shipment_id=99,kind='received',tick=1100,from=endpoint(remote_surface,2),to=endpoint(local_surface,1),
        contents={stack('iron-plate',18)}}}}
end
q=F.query(force,local_surface,1200,10)
iron=q.materials['item/iron-plate'].imports
assert(q.received_partial and not iron.sent_partial and iron.received_partial,
  'Receipt gap at the exact window start was lost or incorrectly reduced dispatch completeness')
local narrower=F.query(force,local_surface,1200,5)
assert(not narrower.received_partial and not narrower.materials['item/iron-plate'].imports.received_partial,
  'Receipt gap before the selected window contaminated fresh complete coverage')
receipt_gap,receipt_seconds=nil,2
q=F.query(force,local_surface,1200,10)
assert(not q.materials['item/iron-plate'].imports.sent_partial and q.materials['item/iron-plate'].imports.received_partial,
  'Short received coverage inherited complete dispatch coverage')
near(q.coverage.sent,10);near(q.coverage.received,2)
T.boundaries=old_boundaries
-- A narrow window must retain both manifests/timestamps of a crossing whose
-- dispatch is much older than its receipt, without traversing all old traffic.
storage={};T.on_housekeeping(0)
local delayed=depart(10000,10,silo,{stack('iron-plate',11,'rare')})
for i=1,512 do
  local old=depart(10000+i,20+i,silo,{stack('stone',1)})
  old.valid=false
end
deliver(delayed,2000,hub,{stack('iron-plate',9,'rare')})
local narrow=F.history(force,local_surface,2000,1,{material='iron-plate'})
assert(#narrow.records==1 and narrow.records[1].tick==10 and narrow.records[1].arrival_tick==2000,
  'Windowed query lost the older dispatch paired with a recent receipt')
near(narrow.records[1].sent[1].count,11);near(narrow.records[1].received[1].count,9)
assert(#F.history(force,local_surface,2000,1,{material='stone'}).records==0)
-- Count physical ring reads after the derived index has been built. Result
-- allocation must be proportional to selected traffic, not retained traffic.
local observations=storage.transfers.boundary_observations
local history=observations.history
local reads=0
observations.history=setmetatable({}, {__index=function(_,key) reads=reads+1;return history[key] end})
F.history(force,local_surface,2000,1)
assert(reads<=3,'Narrow query scanned the old ledger: '..reads)
observations.history=history
-- Copies remain isolated, and an additional delivery at the same query tick
-- must update both the index and the output without a stale tick cache.
narrow.records[1].sent[1].count=999
near(F.history(force,local_surface,2000,1,{material='iron-plate'}).records[1].sent[1].count,11)
local late=depart(20000,1999,silo,{stack('copper-plate',7)})
local before=F.query(force,local_surface,2000,1)
assert(before.materials['item/copper-plate'].exports.received==nil)
deliver(late,2000,hub,{stack('copper-plate',5)})
local after=F.query(force,local_surface,2000,1)
near(after.materials['item/copper-plate'].exports.received,5)
assert(#F.history(force,remote_surface,1998,1,{material='copper-plate'}).records==0,
  'A later destination leaked into an earlier scoped query')
-- A cold script reload reconstructs the same pair index from canonical rings.
package.loaded['scripts.transfers']=nil;T=require('scripts.transfers')
local rebuilt=T.boundaries(force,local_surface,2000,1,{companions=true})
assert(#rebuilt.records==4,'Reload lost a retained companion or duplicated a boundary')
print('TRANSPORT FLOWS PASS: scoped independent boundaries, quality-aware stock events, SA dispatch/legacy receipts and selected-window rates')
