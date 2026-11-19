local Sm, C, B = TREQ("scripts.sampler"), TREQ("scripts.chest_stock"), TREQ("scripts.balance")
local saved_storage, saved_tick = storage, game.tick
local saved_interval=settings.global["ssk-stock-scan-minutes"].value
local saved_data,declared=data,nil
data={extend=function(_,entries) for _,entry in ipairs(entries) do
  if entry.name=="ssk-stock-scan-minutes" then declared=entry end
end end}
dofile("settings.lua");data=saved_data
assert(declared and declared.type=="int-setting" and declared.setting_type=="runtime-global"
  and declared.minimum_value==1 and declared.default_value==5,"expose the 1-minute minimum / 5-minute default as a map setting")
storage={stock={{tick=0,s={}}},stock_basis="stored-with-reservations-v1"}
Sm.init()
assert(#storage.stock==0,"changing stock scope must clear the old trend")
local reads=0
local function chest(id,kind,surface,contents,force)
  local e={valid=true,type=kind,unit_number=id,surface={index=surface},force=force or game.forces.player}
  e.contents=contents
  e.get_inventory=function()
    return {valid=true,get_contents=function() reads=reads+1;return e.contents end}
  end
  C.add(e);C.add(e)
  return e
end
local a=chest(1,"container",1,{{name="steel-plate",count=70},{name="steel-plate",quality="rare",count=31}})
local b=chest(2,"logistic-container",1,{{name="steel-plate",count=9}})
chest(3,"container",2,{{name="steel-plate",count=23}})
chest(4,"container",1,{{name="steel-plate",count=9999}}, {})
local removed=chest(5,"container",1,{{name="steel-plate",count=500}});removed.valid=false
for id=6,103 do chest(id,"container",1,{}) end
assert(C.status().tracked==103,"deduplicate build/clone notifications")
Sm.on_tick(1)
assert(reads<=32 and #storage.stock==0,"bounded work and no partial snapshot, even with no crafting machines")
local late=chest(104,"container",1,{{name="steel-plate",count=1000}})
for tick=2,5 do local before=reads;Sm.on_tick(tick);assert(reads-before<=32) end
assert(Sm.stock(1)["item/steel-plate"].count==110,"ordinary/logistic and mixed-quality counts once; late additions deferred")
assert(Sm.stock(2)["item/steel-plate"].count==23 and Sm.stock(nil)["item/steel-plate"].count==133,"surface scopes")
assert(C.status().tracked==103,"invalid entries removed without dropping late builds")
assert(C.interval()==18000,"stock updates must wait five full game minutes")
local completed_tick=storage.stock[#storage.stock].tick
for tick=completed_tick+1,completed_tick+C.interval()-1 do Sm.on_tick(tick) end
assert(#storage.stock==1 and not C.status().active,"no scan may start during the five-minute cooldown")
assert(Sm.stock_known(1) and not Sm.stock_known(999),"known zero requires a completed surface sample")
late.valid=false;b.contents={};a.contents={{name="steel-plate",count=100}}
for tick=18005,18009 do Sm.on_tick(tick) end
local st=Sm.stock(1)["item/steel-plate"]
local h=storage.stock;local expected_trend=-10/((h[#h].tick-h[1].tick)/3600)
assert(st.count==100 and math.abs(st.per_min-expected_trend)<0.01,"trend uses complete-scan timestamps")
local rows=B.rows(1,600);local found
for _,r in ipairs(rows) do if r.key=="item/steel-plate" then found=r end end
assert(found and found.status=="stored" and found.prod==0 and found.cons==0 and found.stock==100,"stored-only items are visible without production history")
-- A saved batch consists solely of serializable state; continuing it after init must preserve progress.
C.request(36010);C.tick(36010)
local cursor=storage.chest_stock.batch.cursor
Sm.init();assert(storage.chest_stock.batch.cursor==cursor)
for tick=36011,36014 do C.tick(tick) end
assert(Sm.stock(1)["item/steel-plate"].count==100,"resume a partial scan without double counting")
local last=storage.stock[#storage.stock].tick
settings.global["ssk-stock-scan-minutes"].value=1
Sm.on_stock_interval_changed()
assert(C.status().interval==3600 and storage.chest_stock.next_tick==last+3600,"shortening a setting reschedules from the last completed scan")
C.tick(last+3599)
assert(not C.status().active,"the 1-minute minimum is a full cooldown")
C.tick(last+3600)
assert(C.status().active,"a shorter cooldown takes effect without rescanning the registry")
local cursor=storage.chest_stock.batch.cursor
settings.global["ssk-stock-scan-minutes"].value=10
Sm.on_stock_interval_changed()
assert(storage.chest_stock.batch.cursor==cursor,"changing interval must not restart an in-flight scan")
for tick=last+3601,last+3604 do C.tick(tick) end
local finished=storage.stock[#storage.stock].tick
assert(storage.chest_stock.next_tick==finished+36000,"an active scan uses the newly selected cooldown on completion")
settings.global["ssk-stock-scan-minutes"].value=15
Sm.on_stock_interval_changed()
assert(storage.chest_stock.next_tick==finished+54000,"increasing the interval postpones the next scan")
settings.global["ssk-stock-scan-minutes"].value=saved_interval
-- Changing the scope invalidates chest-only baselines. Cargo inventories use
-- their dedicated inventory IDs, never the unrelated rocket recipe/result slots.
storage={stock_basis="physical-chests-v1",stock={{tick=0,s={[1]={["item/iron-plate"]=999}}}}}
C.init();assert(storage.stock_basis=="physical-storage-v2" and #storage.stock==0)
local ids=defines.inventory
local old_pad,old_hub,old_silo=ids.cargo_landing_pad_main,ids.hub_main,ids.rocket_silo_attached_cargo_unit
ids.cargo_landing_pad_main,ids.hub_main,ids.rocket_silo_attached_cargo_unit=101,102,103
for i,kind in ipairs({"cargo-landing-pad","space-platform-hub","rocket-silo"}) do
  local entity={valid=true,type=kind,unit_number=900+i,surface={index=1},force=game.forces.player}
  entity.get_inventory=function(id)
    assert(id==100+i,"Wrong cargo stock inventory")
    return {valid=true,get_contents=function() return {{name="iron-plate",count=i*10}} end}
  end
  C.add(entity);C.add(entity)
end
C.tick(1)
assert(storage.stock[1].s[1]["item/iron-plate"]==60 and C.status().tracked==3,
  "Cargo pads, hubs and loaded rocket cargo must join physical stock exactly once")
local surface=game.surfaces[1]
local find_entities=surface.find_entities_filtered
local old_cargo=ids.cargo_unit;ids.cargo_unit=104
local pods={}
for i,entry in ipairs({{"awaiting_launch","space-platform-hub"},{"ascending","space-platform-hub"},
  {"awaiting_launch","rocket-silo"},{"descending","space-platform-hub"}}) do
  local pod={valid=true,type="cargo-pod",unit_number=950+i,surface=surface,force=game.forces.player,
    cargo_pod_state=entry[1],cargo_pod_origin={valid=true,type=entry[2]}}
  pod.get_inventory=function(id)
    assert(i==1 and id==104,"Only waiting platform cargo belongs to stored stock; attached rocket cargo is already counted")
    return {valid=true,get_contents=function() return {{name="iron-plate",count=100}} end}
  end
  pods[#pods+1]=pod
end
surface.find_entities_filtered=function(filter)
  if filter.type=="cargo-pod" then return pods end
  return find_entities(filter)
end
storage.chest_stock.next_tick=0;C.tick(2)
assert(storage.stock[2].s[1]["item/iron-plate"]==160,
  "Cargo waiting at a platform hatch must survive a scan between hub loading and dispatch")
pods[1].cargo_pod_state="ascending"
storage.chest_stock.next_tick=0;C.tick(3)
assert(storage.stock[3].s[1]["item/iron-plate"]==60,
  "A dispatched pod leaves stored stock exactly once at ascent start")
chest(999,"temporary-container",1,{{name="iron-plate",count=7}})
storage.chest_stock.next_tick=0;C.tick(4)
assert(storage.stock[4].s[1]["item/iron-plate"]==67,
  "Landed cargo's temporary container remains physical stock after receipt")
local active,entity_prototypes=script.active_mods,prototypes.entity
script.active_mods={["space-exploration"]="0.7.64"}
prototypes.entity={["se-cargo-rocket-cargo-pod"]={}}
local recovered={valid=true,type="container",name="se-cargo-rocket-cargo-pod",unit_number=1001,
  surface=surface,force=game.forces.player,get_inventory=function(id)
    assert(id==ids.chest)
    return {valid=true,get_contents=function() return {{name="iron-plate",count=33}} end}
  end}
surface.find_entities_filtered=function(filter)
  if filter.name=="se-cargo-rocket-cargo-pod" then return {recovered} end
  if filter.type=="cargo-pod" then return pods end
  return find_entities(filter)
end
storage.chest_stock.next_tick=0;C.tick(5)
assert(storage.stock[5].s[1]["item/iron-plate"]==100 and storage.chest_stock.entities[1001]==recovered,
  "SE's internally-created padless cargo containers must be discovered without a built event or invented receipt")
script.active_mods,prototypes.entity=active,entity_prototypes
surface.find_entities_filtered=find_entities;ids.cargo_unit=old_cargo
ids.cargo_landing_pad_main,ids.hub_main,ids.rocket_silo_attached_cargo_unit=old_pad,old_hub,old_silo
storage,game.tick=saved_storage,saved_tick
print("CHEST STOCK OK: budget, atomic scans, registry changes, qualities, forces, surfaces, trends, stored-only, resume and runtime intervals")
