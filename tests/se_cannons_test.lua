-- Isolated provider test; no private SE adapter or runtime functions required.
local endpoint_calls=0
package.loaded["scripts.transfer_endpoints"]={snapshot=function(e,kind)
  endpoint_calls=endpoint_calls+1
  if not (e and e.valid and e.force.valid and e.surface.valid) then return nil end
  return {entity=e,unit_number=e.unit_number,surface=e.surface,force=e.force,
    position={x=e.position.x,y=e.position.y},kind=kind}
end}
local C=require("scripts.se_cannons")
script={active_mods={}}
defines={events={on_script_trigger_effect=77},inventory={crafter_output=1,chest=2}}
storage={}
game={tick=0,surfaces={}}
assert(not C.available())
script.active_mods["space-exploration"]="0.7.63";assert(not C.available())
script.active_mods["space-exploration"]="0.7.64";assert(C.available())
local own={valid=true,index=1}
local other={valid=true,index=2}
local entities={}
local a={valid=true,index=1,name="Nauvis"}
local b={valid=true,index=2,name="Orbit"}
local last_filter
local function find(surface,filter)
  last_filter=filter
  local names=type(filter.name)=="table" and filter.name or {filter.name}
  local allowed={};for _,n in ipairs(names) do allowed[n]=true end
  local result={}
  for _,e in ipairs(entities) do
    if e.valid and e.surface==surface and allowed[e.name] and (not filter.force or e.force==filter.force) then
      local p=filter.position
      if not p or (e.position.x-p.x)^2+(e.position.y-p.y)^2<=filter.radius^2 then
        result[#result+1]=e
        if #result==filter.limit then break end
      end
    end
  end
  return result
end
a.find_entities_filtered=function(f) return find(a,f) end
b.find_entities_filtered=function(f) return find(b,f) end
game.surfaces[1]=a;game.surfaces[2]=b
prototypes={entity={["se-delivery-cannon"]={},["se-delivery-cannon-chest"]={}},recipe={
  ["se-delivery-cannon-pack-iron"]={ingredients={{name="se-delivery-cannon-capsule",amount=1},{name="iron-plate",type="item",amount=100}},products={{name="iron-package"}}}}}
local function entity(unit,surface,force,name,x,y,items)
  local e={valid=true,unit_number=unit,surface=surface,force=force,name=name,position={x=x,y=y},items=items or {}}
  e.get_inventory=function() return {valid=true,get_contents=function() return e.items end} end
  e.get_recipe=function() return {name="se-delivery-cannon-pack-iron"} end
  entities[#entities+1]=e;return e
end
local first=entity(10,a,own,"se-delivery-cannon",0,0,{{name="iron-package",quality="rare",count=2}})
local second=entity(20,a,own,"se-delivery-cannon",10,0)
local foreign=entity(30,a,other,"se-delivery-cannon",20,0)
local orbital=entity(40,b,own,"se-delivery-cannon",0,0)
entity(50,a,own,"se-delivery-cannon-chest",0,20,{{name="iron-plate",quality="normal",count=123}})
local function effect(tick,e)
  game.tick=tick
  return {effect_id=C.EFFECT_ID,tick=tick,surface_index=e.surface.index,
    source_position={x=e.position.x-0.5,y=e.position.y-5}}
end
C.init(0)
C.on_effect(effect(10,first));C.on_effect(effect(10,second))
local q=C.query(own,a,10,60)
assert(q.shot_count==2 and #q.observations==2,"Concurrent endpoints were conflated")
assert(last_filter.limit==2 and last_filter.radius==0.05)
for _,r in ipairs(q.observations) do
  assert(r.kind=="cannon_firing_effect" and r.shot_count==1)
  assert(r.sent==nil and r.received==nil and r.destination==nil,"Firing marker invented a payload")
end
-- Without a projectile marker a shot stays unpaired: no destination or receipt.
assert(q.sent==nil and q.received==nil and q.capabilities.sent_manifest and q.capabilities.destination)
-- A valid named source beam takes precedence over a contradictory position.
local marker=effect(20,second)
marker.source_entity={valid=true,name="se-delivery-cannon-beam",surface=a,position={x=-0.5,y=-5}}
C.on_effect(marker)
assert(C.query(own,a,20,60).observations[1].sender.unit_number==first.unit_number)
marker=effect(20,second)
marker.target_entity={valid=true,name="se-delivery-cannon-beam",surface=a,position={x=9.5,y=-5}}
marker.source_position=nil
C.on_effect(marker)
assert(C.query(own,a,20,60).observations[1].sender.unit_number==second.unit_number)
marker=effect(20,first);marker.target_position=marker.source_position;marker.source_position=nil
C.on_effect(marker)
assert(C.query(own,a,20,60).observations[1].sender.unit_number==first.unit_number)
C.on_effect(effect(21,foreign));C.on_effect(effect(22,orbital))
assert(C.query(own,a,22,60).shot_count==5 and C.query(other,a,22,60).shot_count==1)
assert(C.query(own,b,22,60).shot_count==1)
assert(C.query(own,{valid=true,index=1},22,60).shot_count==0,"Reused surface index matched historical reference")
-- Do not choose a nearest or ambiguous sender, or accept another effect ID.
local duplicate=entity(60,a,other,"se-delivery-cannon",0,0)
C.on_effect(effect(23,first));assert(C.query(own,a,23,60).shot_count==5)
duplicate.valid=false
local invalid=effect(24,first);invalid.source_position={x=0,y=0};C.on_effect(invalid)
invalid=effect(24,first);invalid.effect_id="other-effect";C.on_effect(invalid)
invalid=effect(24,first);invalid.source_position={x=0/0,y=0};C.on_effect(invalid)
assert(C.query(own,a,24,60).shot_count==5)
script.active_mods["space-exploration"]="0.7.65";C.on_effect(effect(25,first))
assert(C.query(own,a,25,60).shot_count==5 and not C.query(own,a,25,60).capabilities.firing_effects)
script.active_mods["space-exploration"]="0.7.64"
-- Discovery is read-only ready/stored inventory, not shipment history.
local before=storage.se_cannons.count
local d=C.discover(a,own)
assert(#d.cannons==2 and #d.receivers==1 and d.inventory_kind=="current_contents")
assert(d.cannons[1].ready_packages[1].count==2 and d.cannons[1].ready_payload[1].count==200)
assert(d.cannons[1].ready_payload[1].quality=="rare" and d.cannons[1].declared_payload.count_per_package==100)
assert(d.receivers[1].stored_items[1].count==123 and d.receivers[1].received==nil)
assert(storage.se_cannons.count==before and d.cannons[1].sent==nil)
first.items[1].count=9
assert(d.cannons[1].ready_packages[1].count==2,"Inventory snapshot aliased mutable engine contents")
local s=storage.se_cannons
package.loaded["scripts.se_cannons"]=nil;C=require("scripts.se_cannons")
assert(storage.se_cannons==s and C.query(own,a,25,60).shot_count==5,"Reload lost observations")
for i=1,260 do entity(1000+i,a,own,"se-delivery-cannon-chest",30,i) end
d=C.discover(a,own)
assert(d.truncated and #d.cannons+#d.receivers==256 and last_filter.limit==257,"Discovery bound missing")
storage.se_cannons=nil;C.init(0)
for i=1,4100 do C.on_effect(effect(i,first)) end
q=C.query(own,a,4100,600)
assert(q.shot_count==4096 and q.truncated and storage.se_cannons.count==4096,"Retention overflow was hidden")
assert(C.query(own,a,4100,1).shot_count==61,"Time window filtering is inconsistent")
C.prune(3600000*60+5000)
assert(storage.se_cannons.count==0)
print("SE CANNONS PASS: versioned firing witnesses, concurrent/ambiguous endpoints, unknown manifests, force/time/surface isolation, inventory distinction and bounds")
