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
storage,game.tick=saved_storage,saved_tick
print("CHEST STOCK OK: budget, atomic scans, registry changes, qualities, forces, surfaces, trends, stored-only, resume and runtime intervals")
