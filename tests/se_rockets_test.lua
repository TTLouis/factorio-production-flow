local R=require("scripts.se_rockets")
storage={}
script={active_mods={}}
defines={events={se_on_cargo_rocket_launched=501,se_on_cargo_rocket_padless=502}}
assert(not R.available())
script.active_mods["space-exploration"]="0.7.64"
assert(R.available())
local a={valid=true,index=1,name="Nauvis"}
local b={valid=true,index=2,name="Orbit"}
local own={valid=true,index=1}
local other={valid=true,index=2}
game={tick=0,forces={player=own,other=other},surfaces={[1]=a,[2]=b}}
prototypes={item={iron={stack_size=100},copper={stack_size=1}}}
local cargo_modifier,pad_modifier=.9,.8
local zones={
  [1]={surface_index=1,type="planet",stellar_position={x=4,y=8},star_gravity_well=20,planet_gravity_well=10},
  [2]={surface_index=2,type="orbit",parent_index=1},
}
remote={interfaces={['space-exploration']={get_zone_from_zone_index=true,get_cargo_loss=true,get_survivability_loss=true}},
 call=function(_,method,q)
  if method=="get_cargo_loss" then return cargo_modifier end
  if method=="get_survivability_loss" then return pad_modifier end
  return zones[q.zone_index]
end}
R.init(0)
local function event(tick,unit,from,to,force,items)
  game.tick=tick
  return {tick=tick,unit_number=unit,launchpad={valid=true,name="se-rocket-launch-pad",unit_number=unit,surface=from,force=force,position={x=unit,y=0}},
    force_name=force==own and "player" or "other",zone_index=from.index,zone_name=from.name,
    destination_zone_index=to.index,destination_zone_name=to.name,
    launched_contents=items or {{name="iron",quality="normal",count=100},{name="iron",quality="rare",count=2}}}
end
local e=event(10,100,a,b,own)
e.landing_pad={valid=true,unit_number=101,name="cargo-landing-pad",surface=b,force=own,position={x=0,y=0}}
R.on_launch(e);R.on_launch(e)
assert(storage.se_rockets.count==1,"Duplicate event")
e.launched_contents[1].count=9999
local q=R.query(own,a,10,60)
assert(#q.exports==1 and #q.imports==0 and q.exports[1].items[1].count==100)
assert(q.exports[1].items[2].quality=="rare" and q.exports[1].items[2].count==2)
assert(q.exports[1].received==nil and q.records[1].received==nil and q.records[1].arrival_tick==nil)
assert(q.records[1].sender.unit_number==100 and q.records[1].sender.position.x==100)
assert(#R.query(own,b,10,60).imports==1,"Incoming route lost")
local loss_base=1100/101100
assert(math.abs(q.records[1].cargo_loss-loss_base*.9)<1e-9)
assert(math.abs(q.records[1].pad_miss-loss_base*.8)<1e-9)
cargo_modifier,pad_modifier=.81,.64
R.on_launch(event(20,200,b,a,own,{{name="copper",count=40}}))
assert(math.abs(storage.se_rockets.history[1].cargo_loss-loss_base*.9)<1e-9,"Research rewrote the old launch")
assert(math.abs(storage.se_rockets.history[2].cargo_loss-loss_base*.81)<1e-9)
assert(storage.se_rockets.history[2].pad_miss==1,"Padless route must use full loss")
R.on_launch(event(30,300,a,b,other))
R.on_launch(event(40,400,a,a,own))
q=R.query(own,a,40,60)
assert(q.shipments==2 and #q.imports==1 and #q.exports==1,"Scope/force/same-surface isolation")
assert(R.query(other,a,40,60).shipments==1)
assert(R.query(own,a,40,60,"copper").shipments==1)
assert(#R.query(own,a,40,60,"missing").materials==2)
assert(R.surfaces(own)[b.index] and not R.surfaces({})[a.index])
package.loaded['scripts.se_rockets']=nil
R=require('scripts.se_rockets')
assert(R.query(own,a,40,60).shipments==2,"Reload lost history")
R.on_padless{tick=50,unit_number=100,launchpad=e.launchpad,destination_zone_index=2}
assert(storage.se_rockets.history[1].status=='padless' and storage.se_rockets.history[1].received==nil)
-- Ambiguous overlapping launches from one pad must not be arbitrarily resolved.
R.on_launch(event(60,500,a,b,own));local overlap=event(70,500,a,b,own);R.on_launch(overlap)
R.on_padless{tick=80,unit_number=500,launchpad=overlap.launchpad,destination_zone_index=2}
assert(storage.se_rockets.history[5].status=='unconfirmed' and storage.se_rockets.history[6].status=='unconfirmed')
-- Retained endpoints survive removal; reused surface indexes must not match.
b.valid=false
assert(R.query(own,a,80,60).shipments==4)
assert(R.query(own,{valid=true,index=b.index},80,60).shipments==0)
b.valid=true
local old=storage.se_rockets
storage.se_rockets=nil;R.init(0)
for i=1,4100 do R.on_launch(event(i,i,a,b,own,{{name='iron',count=1}})) end
q=R.query(own,a,4100,600)
assert(storage.se_rockets.count==4096 and q.truncated and q.shipments==4096,"Bounded history / overflow disclosure")
R.prune(3600000*60+5000)
assert(storage.se_rockets.count==0 and next(storage.se_rockets.seen)==nil,"Retention/dedup state leaked")
storage.se_rockets=nil;R.init(0)
other.valid=true
R.on_launch(event(1,1,a,b,other,{{name='iron',count=1}}))
other.valid=false;other.index=nil
setmetatable(other,{__index=function(_,key) if key=='index' then error('Invalid force index access') end end})
for i=2,4100 do R.on_launch(event(i,i,a,b,own,{{name='iron',count=1}})) end
assert(R.query(own,a,4100,600).shipments==4096,'Deleted-force history broke overflow')
print('SE ROCKETS PASS: exact qualities, duplicate/reload, directional scope, force isolation, unknown receipts, padless ambiguity and bounded retention')
