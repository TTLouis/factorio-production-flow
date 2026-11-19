local F=require("scripts.transport_flows")
local T=require("scripts.transfers")
local R=require("scripts.se_rockets")
local C=require("scripts.se_cannons")
local force={index=1,valid=true,platforms={}}
local other={index=2,valid=true}
local local_surface={index=1,name="Nauvis",valid=true}
local remote_surface={index=2,name="Orbit",valid=true}
local replacement={index=1,name="Replacement",valid=true}
defines={events={se_on_cargo_rocket_launched=10,on_script_trigger_effect=11,
  on_cargo_pod_finished_ascending=1,on_cargo_pod_finished_descending=2,on_cargo_pod_delivered_cargo=3},
  inventory={cargo_unit=1,chest=2},cargo_destination={station=1,surface=2}}
script={active_mods={}}
game={tick=1200,forces={player=force}}
storage={}
prototypes={item={['iron-plate']={},['copper-plate']={},['water-barrel']={}}}
local function near(a,b)assert(a and math.abs(a-b)<1e-9,tostring(a).." ~= "..tostring(b))end
local function endpoint(surface,id)return{surface=surface,id=id,zone=id,name=surface.name}end
local function stack(name,count,quality)return{name=name,count=count,quality=quality or "normal"}end
local function rocket(id,from,to,tick,sent,received,arrival,owner)
  local s=storage.se_rockets
  s.count=s.count+1;s.history[s.count]={id=id,key=tostring(id),force=owner or force,
    from=endpoint(from,from.index),to=endpoint(to,to.index),departure_tick=tick,
    sent=sent,received=received,arrival_tick=arrival}
end

assert(F.query(force,local_surface,1200,10).provider==nil)
script.active_mods['space-exploration']='0.7.64'
R.init(0);C.init(0)
rocket(1,local_surface,remote_surface,700,{stack('iron-plate',100),stack('iron-plate',20,'rare')},
  {stack('iron-plate',90)},900)
rocket(2,remote_surface,local_surface,500,{stack('copper-plate',80)},
  {stack('copper-plate',70)},800) -- Departure is outside the selected window.
rocket(3,remote_surface,local_surface,850,{stack('iron-plate',50)},nil,nil)
rocket(4,local_surface,local_surface,900,{stack('iron-plate',1000)},nil,nil)
rocket(5,local_surface,remote_surface,1250,{stack('iron-plate',1000)},nil,nil)
rocket(6,local_surface,remote_surface,900,{stack('iron-plate',1000)},nil,nil,other)
rocket(7,replacement,remote_surface,900,{stack('iron-plate',1000)},nil,nil)
rocket(8,local_surface,remote_surface,1000,{stack('water-barrel',5)},nil,nil)
storage.se_cannons.count=1;storage.se_cannons.history[1]={id=1,tick=900,sender={surface=local_surface,force=force}}
local q=F.query(force,local_surface,1200,10)
assert(q.provider=='se' and q.period_seconds==10 and q.unknown.unpaired_cannon_observations==1)
local iron=q.materials['item/iron-plate']
assert(iron.exports.activity and iron.exports.sent_known and iron.exports.received_known)
near(iron.exports.sent,120);near(iron.exports.received,90)
near(iron.exports.sent_rate,12);near(iron.exports.received_rate,9)
assert(#iron.exports.routes==1 and iron.exports.routes[1].method=='rocket' and iron.exports.routes[1].remote_name=='Orbit',
  'Hover route metadata lost method/surface or duplicated qualities as routes')
iron.exports.routes[1].remote_name='mutated presentation'
assert(F.query(force,local_surface,1200,10).materials['item/iron-plate'].exports.routes[1].remote_name=='Orbit',
  'Presentation route metadata mutated the provider')
assert(iron.exports.sent_partial and iron.exports.received_partial,
  'known rocket evidence must not claim complete all-method SE coverage')
near(iron.imports.sent,50);assert(iron.imports.received==nil and iron.imports.received_rate==nil)
assert(iron.imports.history.material=='iron-plate' and iron.imports.history.method=='rocket')
local copper=q.materials['item/copper-plate']
assert(copper.imports.sent==nil);near(copper.imports.received,70)
assert(not copper.exports.activity and copper.exports.sent==nil)
assert(q.materials['item/water-barrel'] and not q.materials['fluid/water'], 'barrels remain item cargo')
assert(#q.events==4)
local net=0
for _,event in ipairs(q.events) do
  net=net+event.delta
  assert(event.surface_index==1 and event.stats_included==false)
  assert(not(event.material=='item/iron-plate' and event.delta>0), 'incoming source dispatch is not a local receipt')
end
near(net,-55) -- -120 iron +70 copper -5 barrels; destination receipts are not local stock.
local events=F.events(force,local_surface,1200,10,{material='iron-plate'})
assert(#events==2 and events[1].quality=='normal' and events[2].quality=='rare')
local h=F.history(force,local_surface,1200,10,{material='iron-plate',direction='exports'})
assert(#h.records==1 and #h.materials==3 and h.records[1].sent[2].quality=='rare')
assert(#F.query(force,replacement,1200,10).events==1)
rocket(9,remote_surface,local_surface,1000,{stack('stone',10)},{},1100)
local empty_receipt=F.query(force,local_surface,1200,10).materials['item/stone'].imports
assert(empty_receipt.received_known and empty_receipt.received==0,
  'an explicitly measured empty receipt is distinct from an unknown receipt')
storage.se_rockets.history[storage.se_rockets.count]=nil;storage.se_rockets.count=storage.se_rockets.count-1
assert(not next(F.query({index=1,valid=false},local_surface,1200,10).materials))
assert(not next(F.query(force,local_surface,1200,-1).materials))
assert(not next(F.query(force,local_surface,0/0,10).materials))
local at_start=F.query(force,local_surface,600,100)
near(at_start.period_seconds,10)
storage.se_rockets.dropped[1]={force=force,tick=900}
assert(F.query(force,local_surface,1200,10).truncated)
-- Paired SE cannon shots: packing is already in statistics, the landing insert is not.
storage.se_cannons.count=2;storage.se_cannons.history[2]={id=2,tick=1000,arrival_tick=1100,status='received',
  sender={surface=local_surface,force=force,zone=1},
  destination={surface=remote_surface,zone=2,name='Orbit',position={x=0,y=0}},
  sent={stack('copper-plate',100)},received={stack('copper-plate',100)}}
local function cannon_events(surface)
  local out={}
  for _,event in ipairs(F.query(force,surface,1200,10).events) do if event.method=='cannon' then out[#out+1]=event end end
  return out
end
local cannon_sent,cannon_received=cannon_events(local_surface),cannon_events(remote_surface)
assert(#cannon_sent==1 and cannon_sent[1].kind=='sent' and cannon_sent[1].stats_included==true,'Cannon packing counted twice')
assert(#cannon_received==1 and cannon_received[1].kind=='received' and cannon_received[1].stats_included==false
  and cannon_received[1].delta==100,'Cannon landing insert omitted from stock estimates')
storage.se_cannons.history[2]=nil;storage.se_cannons.count=1
script.active_mods['space-exploration']='0.7.65'
assert(F.query(force,local_surface,1200,10).events[1].stats_included==nil,
  'a version without audited statistics semantics cannot inherit the exclusion flag')

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
q=F.query(force,local_surface,1200,10)
assert(q.provider=='sa' and q.coverage_known)
iron=q.materials['item/iron-plate']
near(iron.exports.sent,24);near(iron.exports.received,20)
assert(iron.exports.routes[1].method=='cargo-pod' and iron.exports.routes[1].remote_name=='Orbit',
  'SA hover route metadata lost the remote surface or transport method')
assert(not iron.exports.sent_partial and not iron.exports.received_partial)
near(q.materials['item/copper-plate'].exports.sent,7)
assert(q.materials['item/copper-plate'].exports.received==nil)
near(F.query(force,remote_surface,1200,10).materials['item/iron-plate'].imports.received,20)
events=F.events(force,local_surface,1200,10,{material='item/iron-plate'})
assert(#events==2 and events[1].stats_included==false)
near(events[1].delta+events[2].delta,-24)
h=F.history(force,remote_surface,1200,7,{material='iron-plate'})
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
print('TRANSPORT FLOWS PASS: scoped independent boundaries, quality-aware stock events, SA dispatch/legacy receipts, SE unknowns and selected-window rates')
