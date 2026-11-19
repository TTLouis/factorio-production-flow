-- Exact SE 0.7.64 rocket receipts from SE's own launch inventory.
local R=require("scripts.se_rockets")
local Exchanges=require("scripts.transfer_exchanges")
storage={}
script={active_mods={["space-exploration"]="0.7.64"}}
defines={events={se_on_cargo_rocket_launched=501,se_on_cargo_rocket_padless=502},inventory={chest=2}}
remote=nil
prototypes={item={iron={stack_size=100},copper={stack_size=100},capsule={stack_size=1}}}
local a={valid=true,index=1,name="Nauvis"}
local b={valid=true,index=2,name="Orbit"}
local own={valid=true,index=1}
local se_inventories={}
game={tick=0,forces={player=own},surfaces={[1]=a,[2]=b},
  get_script_inventories=function(mod)
    assert(mod=="space-exploration","Read another mod's inventories")
    return {["space-exploration"]=se_inventories}
  end}

local function inventory(items)
  local inv={valid=true,items=items}
  inv.get_contents=function()
    assert(inv.valid,"Read a destroyed inventory")
    local out={}
    for i,v in ipairs(inv.items) do out[i]={name=v.name,quality=v.quality or "normal",count=v.count} end
    return out
  end
  return inv
end
local function se_launch(items)
  local inv=inventory(items)
  se_inventories[#se_inventories+1]=inv
  return inv
end
local function pad(unit,surface,items)
  local chest=inventory(items or {})
  chest.get_item_count=function(id)
    local n=0
    for _,v in ipairs(chest.items) do if v.name==id.name and (v.quality or "normal")==id.quality then n=n+v.count end end
    return n
  end
  -- Usable empty slots after landing; tests set chest.empty for a full pad.
  chest.count_empty_stacks=function(filtered,bar)
    assert(filtered==false and bar==false,"Counted filtered or bar-blocked slots as free")
    return chest.empty or 20-#chest.items
  end
  return {valid=true,unit_number=unit,name="se-rocket-landing-pad",surface=surface,force=own,position={x=unit,y=0},
    chest=chest,get_inventory=function(id) assert(id==defines.inventory.chest);return chest end}
end
local function launch(tick,unit,items,landing)
  game.tick=tick
  R.on_launch{tick=tick,unit_number=unit,force_name="player",zone_index=1,zone_name="Nauvis",
    destination_zone_index=2,destination_zone_name="Orbit",landing_pad=landing,
    launchpad={valid=true,name="se-rocket-launch-pad",unit_number=unit,surface=a,force=own,position={x=0,y=0}},
    launched_contents=items}
  return storage.se_rockets.history[storage.se_rockets.count]
end
local function run(from,to) for t=from,to do game.tick=t;R.on_tick(t) end end

R.init(0)
-- 1. Pad landing: the last post-loss read becomes the exact receipt.
local cargo={{name="iron",count=100},{name="copper",quality="rare",count=40}}
local inv=se_launch(cargo)
local landing=pad(900,b)
local r=launch(10,100,cargo,landing)
assert(r.cargo_inventory==inv and storage.se_rockets.tracking[r.id]==r,"Launch inventory not claimed")
run(11,400)
inv.items={{name="iron",count=88},{name="copper",quality="rare",count=40}} -- SE transition loss
run(401,760)
-- SE moves the cargo into the pad and destroys its inventory on landing.
landing.chest.items={{name="iron",count=88},{name="copper",quality="rare",count=40},{name="capsule",count=1}}
inv.valid=false
run(761,761)
assert(r.status=="received" and r.arrival_tick==761 and r.receipt=="pad","Pad landing not confirmed")
assert(#r.received==2 and r.received[1].name=="copper" and r.received[1].quality=="rare" and r.received[1].count==40)
assert(r.received[2].name=="iron" and r.received[2].count==88,"Receipt ignored the in-flight loss")
assert(r.sent[2].count==100,"Sent manifest rewritten")
assert(r.cargo_inventory==nil and r.landing_entity==nil and next(storage.se_rockets.tracking)==nil,"Landed rocket still tracked")
local q=R.query(own,b,800,600)
assert(q.imports[1].records[1].received[2].count==88)
local tick,kind,count=Exchanges.observation({direction="imports",method="rocket",tick=r.departure_tick,
  arrival_tick=r.arrival_tick,sent=r.sent,received=r.received,cargo_loss=.1,pad_miss=.1,status=r.status},"iron")
assert(tick==761 and kind=="received" and count==88,"Measured receipt fell back to an estimate")

-- 2. Identical unclaimed inventories are ambiguous: no receipt is guessed.
se_inventories={}
local same={{name="iron",count=5}}
se_launch(same);se_launch(same)
r=launch(1000,200,same,pad(901,b))
assert(r.cargo_inventory==nil and r.received==nil,"Ambiguous inventory claimed")

-- 3. A claimed inventory is never claimed twice; the new launch takes its own.
se_inventories={}
local first_inv=se_launch(same)
local first=launch(1100,300,same,pad(902,b))
local second_inv=se_launch(same)
local second=launch(1101,301,same,pad(903,b))
assert(first.cargo_inventory==first_inv and second.cargo_inventory==second_inv,"Claim crossed shipments")

-- 4. Off-pad landings spread cargo over pods: status padless, Received unknown.
R.on_padless{tick=1200,unit_number=300,launchpad={valid=true,force=own},destination_zone_index=2}
assert(first.status=="padless")
first_inv.valid=false
run(1201,1201)
assert(first.status=="padless" and first.received==nil and first.landed_tick==1201,"Padless shipment claimed a pad receipt")

-- 5. A pad holding fewer items than landed (full/emptied) leaves Received unknown.
second_inv.items={{name="iron",count=4}}
run(1202,1230)
second_inv.valid=false
run(1231,1231)
assert(second.received==nil and second.status=="unconfirmed" and second.receipt=="pad-mismatch","Unverified pad receipt")

-- 6. A destroyed landing pad leaves Received unknown.
se_inventories={}
local lost_pad=pad(904,b)
local lost_inv=se_launch(same)
local lost=launch(1300,400,same,lost_pad)
lost_pad.valid=false;lost_inv.valid=false
run(1301,1301)
assert(lost.received==nil and lost.receipt=="pad-unavailable")

-- 7. Zone (no pad) targets have no receipt either.
se_inventories={}
local zone_inv=se_launch(same)
local zone=launch(1400,500,same,nil)
zone_inv.valid=false
run(1401,1401)
assert(zone.received==nil and zone.status=="unconfirmed")

-- 8. Other SE versions keep dispatch-only history.
script.active_mods["space-exploration"]="0.7.63"
se_inventories={}
se_launch(same)
r=launch(1500,600,same,pad(905,b))
assert(r and r.cargo_inventory==nil,"Uninspected SE version tracked")
script.active_mods["space-exploration"]="0.7.64"

-- 9. Old saves gain tracking state; reload keeps in-flight tracking.
storage.se_rockets.tracking=nil
assert(R.init(0).tracking,"Tracking state not migrated")
se_inventories={}
local kept_inv=se_launch(same)
local kept=launch(1600,700,same,pad(906,b))
package.loaded["scripts.se_rockets"]=nil;R=require("scripts.se_rockets")
assert(storage.se_rockets.tracking[kept.id]==kept and kept.cargo_inventory==kept_inv,"Reload lost tracking")

-- 10. Only a pad with a usable empty slot after landing proves SE inserted
-- every launched stack; stock already on the pad never stands in for cargo.
local landings=0
local function land_on(stocked,after,empty,observe)
  landings=landings+1
  local t0=1700+landings*100
  se_inventories={}
  local target=pad(907+landings,b,stocked)
  local flight=se_launch({{name="iron",count=100}})
  local r=launch(t0,800+landings,{{name="iron",count=100}},target)
  assert(r.departure_tick==t0,"Landing fixture reused an earlier shipment")
  run(t0+1,t0+60)
  if observe then observe(target) end
  target.chest.items,target.chest.empty=after,empty
  flight.valid=false
  run(t0+61,t0+61)
  return r
end
-- Full pad: 500 held, SE inserts none and destroys the cargo.
local full=land_on({{name="iron",count=500}},{{name="iron",count=500}},0)
assert(full.received==nil and full.status=="unconfirmed" and full.receipt~="pad",
  "Existing pad stock counted as a full rocket receipt")
-- Partial insertion: 300 held, 30 of 100 fit before the pad filled.
local partial=land_on({{name="iron",count=300}},{{name="iron",count=330}},0)
assert(partial.received==nil and partial.status=="unconfirmed","Partial insertion counted as a rocket receipt")
-- Empty at the last observation, filled before SE landed (the same-tick
-- window): the full pad after landing still leaves Received unknown.
local late=land_on({},{{name="iron",count=500}},0,function(target) assert(target.chest.count_empty_stacks(false,false)>0) end)
assert(late.received==nil and late.status=="unconfirmed","A pad filled just before landing counted as a receipt")
-- Manual launch into a stocked pad with room: every stack went in, so the
-- landed cargo is the receipt, not the pad's total.
local roomy=land_on({{name="iron",count=300}},{{name="iron",count=400},{name="capsule",count=1}},nil)
assert(roomy.status=="received" and roomy.receipt=="pad" and roomy.received[1].count==100,
  "A stocked pad with room lost its exact receipt")
assert(full.receipt=="pad-full" and partial.receipt=="pad-full" and late.receipt=="pad-full","Unknown receipt reason")

-- 11. Overflow eviction also drops tracking.
storage.se_rockets=nil;R.init(0)
se_inventories={}
se_launch(same)
local evicted=launch(1,1,same,pad(907,b))
assert(storage.se_rockets.tracking[evicted.id])
for i=2,4097 do launch(i,i,{{name="iron",count=1}},nil) end
assert(storage.se_rockets.tracking[evicted.id]==nil,"Evicted record still tracked")
print("SE ROCKET RECEIPTS PASS: launch inventory claim, post-loss pad receipts, ambiguity, padless/pad-lost/zone/mismatch/full-pad unknowns, version gate, migration and eviction")
