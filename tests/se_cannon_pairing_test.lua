-- SE 0.7.64 cannon shots: beam -> projectile pairing, payload identity,
-- landing outcome and the transport data view of paired shots.
package.loaded["scripts.transfer_endpoints"]={snapshot=function(e,kind,zone)
  if not (e and e.valid and e.force.valid and e.surface.valid) then return nil end
  return {entity=e,unit_number=e.unit_number,name=e.name,surface=e.surface,force=e.force,
    position={x=e.position.x,y=e.position.y},kind=kind,zone=zone}
end}
package.loaded["scripts.se_rockets"]={query=function() return {records={},seconds=0,truncated=false} end}
local C=require("scripts.se_cannons")
local D=require("scripts.se_transfer_data")
script={active_mods={["space-exploration"]="0.7.64"}}
defines={events={on_script_trigger_effect=77},inventory={crafter_output=1,chest=2}}
storage={}
local own={valid=true,index=1}
local other={valid=true,index=2}
local a={valid=true,index=1,name="nauvis"}
local b={valid=true,index=2,name="se-orbit"}
game={tick=0,surfaces={[1]=a,[2]=b}}
local zone_calls=0
remote={interfaces={["space-exploration"]={get_zone_from_surface_index=true}},call=function(mod,method,q)
  assert(mod=="space-exploration" and method=="get_zone_from_surface_index")
  zone_calls=zone_calls+1
  return {index=q.surface_index+10,name=q.surface_index==1 and "Nauvis" or "Nauvis Orbit"}
end}
prototypes={entity={},recipe={
  ["se-delivery-cannon-pack-iron"]={ingredients={{name="se-delivery-cannon-capsule",amount=1},{name="iron-plate",type="item",amount=100}},products={{name="iron-package"}}},
  ["se-delivery-cannon-pack-copper"]={ingredients={{name="se-delivery-cannon-capsule",amount=1},{name="copper-plate",type="item",amount=50}},products={{name="copper-package"}}}}}
local entities={}
local function find(surface,f)
  local out={}
  for _,e in ipairs(entities) do
    if e.valid and e.surface==surface and e.name==f.name then
      local p=f.position
      local r=f.radius or 0.5
      if not p or (e.position.x-p.x)^2+(e.position.y-p.y)^2<=r^2 then out[#out+1]=e;if #out==f.limit then break end end
    end
  end
  return out
end
a.find_entities_filtered=function(f) return find(a,f) end
b.find_entities_filtered=function(f) return find(b,f) end
local function cannon(unit,x,y,slot,recipe,recipe_quality)
  local e={valid=true,unit_number=unit,name="se-delivery-cannon",surface=a,force=own,position={x=x,y=y},slot=slot,recipe=recipe,recipe_quality=recipe_quality}
  e.get_inventory=function(id)
    assert(id==defines.inventory.crafter_output)
    return {valid=true,[1]=e.slot and {valid_for_read=true,name=e.slot.name,quality={name=e.slot.quality}} or {valid_for_read=false}}
  end
  e.get_recipe=function()
    if not e.recipe then return nil end
    return prototypes.recipe[e.recipe],e.recipe_quality and {name=e.recipe_quality} or nil
  end
  entities[#entities+1]=e
  return e
end
local function chest(surface,x,y)
  local e={valid=true,unit_number=#entities+500,name="se-delivery-cannon-chest",surface=surface,force=own,position={x=x,y=y}}
  entities[#entities+1]=e
  return e
end
local function beam(tick,c)
  game.tick=tick
  C.on_effect{effect_id=C.EFFECT_ID,tick=tick,surface_index=c.surface.index,
    source_entity={valid=true,name="se-delivery-cannon-beam",surface=c.surface,position={x=c.position.x-0.5,y=c.position.y-5}}}
  return storage.se_cannons.history[(storage.se_cannons.first-1+storage.se_cannons.count-1)%4096+1]
end
local function projectile(tick,surface,x,y,force)
  game.tick=tick
  C.on_effect{effect_id=C.PROJECTILE_EFFECT_ID,tick=tick,surface_index=surface.index,
    source_entity={valid=true,name="se-delivery-cannon-capsule-artillery-projectile",surface=surface,
      force=force or own,position={x=x,y=y-100}}}
end
local function impact(tick,surface,x,y)
  game.tick=tick
  C.on_effect{effect_id=C.IMPACT_EFFECT_ID,tick=tick,surface_index=surface.index,
    source_entity={valid=true,name="se-delivery-cannon-capsule-explosion",surface=surface,position={x=x,y=y}}}
end
local function run(from,to) for t=from,to do game.tick=t;C.on_tick(t) end end

C.init(0)
-- 1. Package still in the slot: exact name/quality; whole insert -> receipt.
local iron=cannon(1,0,0,{name="iron-package",quality="rare"},"se-delivery-cannon-pack-iron","rare")
local target=chest(b,5.5,7.5)
local r=beam(60,iron)
assert(r.sent[1].name=="iron-plate" and r.sent[1].quality=="rare" and r.sent[1].count==100 and r.package=="iron-package")
assert(r.destination==nil and r.status=="firing-observed")
projectile(60,b,5.5,7.5)
assert(r.destination.surface==b and r.destination.position.y==7.5 and r.destination.zone==12 and r.eta==180)
assert(r.sender.zone==11 and r.status=="in-flight")
run(61,180)
assert(r.status=="in-flight" and r.received==nil,"Settled before SE's landing tick completed")
run(181,181)
assert(r.status=="received" and r.arrival_tick==180 and r.received[1].count==100 and r.received[1].quality=="rare")
assert(r.received~=r.sent and r.received[1]~=r.sent[1],"Receipt aliased the sent manifest")
assert(r.receiver.unit_number==target.unit_number and r.receiver.zone==12)
assert(next(storage.se_cannons.in_flight)==nil)

-- 2. Last package fired (slot now empty): the recipe and its quality name it.
local copper=cannon(2,20,0,nil,"se-delivery-cannon-pack-copper","uncommon")
r=beam(200,copper)
assert(r.sent[1].name=="copper-plate" and r.sent[1].quality=="uncommon" and r.sent[1].count==50)
-- No recipe and no package: payload stays unknown.
copper.recipe=nil
assert(beam(201,copper).sent==nil)

-- 3. Interception: a beam without projectile stays unpaired; the next beam
--    takes the projectile, never the earlier shot.
local lost=beam(300,iron)
local paired=beam(300,copper)
projectile(300,b,5.5,7.5)
assert(lost.destination==nil and paired.destination~=nil,"Projectile paired with an older beam")
-- Stale beams, other forces and projectiles without beams are ignored.
local stale=beam(310,iron);projectile(311,b,5.5,7.5)
assert(stale.destination==nil)
local foreign=beam(320,iron);projectile(320,b,5.5,7.5,other)
assert(foreign.destination==nil)
projectile(330,b,5.5,7.5)
local count=0;for _ in pairs(storage.se_cannons.in_flight) do count=count+1 end
assert(count==1,"Unmatched projectile created a shipment")

-- 4. A spill explosion at the target on landing means a partial receipt.
local spilled=beam(400,iron);projectile(400,b,30,30)
impact(520,b,30,30)
run(521,521)
assert(spilled.status=="spilled" and spilled.received==nil and spilled.landed_tick==520)
-- An explosion elsewhere or before landing does not mark the shot.
local fine=beam(600,iron);projectile(600,b,5.5,7.5)
impact(700,b,5.5,7.5);impact(720,b,60,60)
run(721,721)
assert(fine.status=="received","Unrelated explosion marked a whole delivery")
-- Two same-target landings with one explosion: neither is claimed whole.
local x1=beam(800,iron);projectile(800,b,5.5,7.5)
local x2=beam(800,copper);projectile(800,b,5.5,7.5)
impact(920,b,5.5,7.5);run(921,921)
assert(x1.status=="spilled" and x2.status=="spilled")

-- 5. No receiver chest, or a deleted surface, leaves Received unknown.
local open=beam(1000,iron);projectile(1000,b,90,90);run(1121,1121)
assert(open.status=="arrived" and open.received==nil)
local gone=beam(1200,iron);projectile(1200,b,5.5,7.5)
b.valid=false;run(1321,1321);b.valid=true
assert(gone.status=="lost" and gone.received==nil)

-- 6. Transport data: exports at the cannon, imports at the target chest.
copper.recipe="se-delivery-cannon-pack-copper"
local q=D.query(own,a,1400,60)
local exports=0
for _,rec in ipairs(q.records) do if rec.direction=="exports" then exports=exports+1 end end
local first=D.query(own,a,200,200).groups.exports[1]
assert(first and first.remote.zone==12 and first.methods[1].method=="cannon","Paired shot not an export route")
local imports=D.query(own,b,200,200)
assert(#imports.groups.imports==1 and imports.groups.imports[1].remote.zone==11)
local rec=imports.records[1]
assert(rec.direction=="imports" and rec.received[1].count==100 and rec.arrival_tick==180 and rec.unknown_payload==false)
assert(#D.query(own,b,200,200,{material="iron-plate"}).records==1)
assert(#D.query(own,a,1400,1400).unpaired>=3,"Unpaired shots disappeared")

-- 7. Old saves gain in-flight state; eviction clears it.
storage.se_cannons.in_flight=nil
assert(C.init(0).in_flight)
storage.se_cannons=nil;C.init(0)
local evicted=beam(1,iron);projectile(1,b,5.5,7.5)
assert(storage.se_cannons.in_flight[evicted.id])
for i=2,4097 do beam(i,iron) end
assert(storage.se_cannons.in_flight[evicted.id]==nil,"Evicted shot still in flight")

-- 8. Other SE versions record nothing.
script.active_mods["space-exploration"]="0.7.65"
local before=storage.se_cannons.count
beam(5000,iron)
assert(storage.se_cannons.count==before)
print("SE CANNON PAIRING PASS: beam/projectile order, slot and recipe payloads, interception, spills, missing chest/surface, routes and migration")
