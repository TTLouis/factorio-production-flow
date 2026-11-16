local Sampler = require("scripts.sampler")
local ChestStock = require("scripts.chest_stock")
local Watch = require("scripts.watch")
local key = "item/iron-plate"
settings = { global = { ["ssk-window-seconds"]={value=60}, ["ssk-stock-scan-minutes"]={value=5} } }
game = { tick=40000*60, forces={player={}}, surfaces={} }
storage = {}
Sampler.init()
local function bin(id, seconds)
  return { id=id, secs=seconds, first=id*seconds, last=(id+1)*seconds,
    rec={ [1]={old={c=30,n=30}}, [2]={kept={c=60,n=60}} },
    stat={ [1]={[key]={i=30,o=10}}, [2]={[key]={i=60,o=20}} },
    coverage={ [0]={id*seconds,(id+1)*seconds}, [1]={id*seconds,(id+1)*seconds}, [2]={id*seconds,(id+1)*seconds} } }
end
storage.bins[1]=bin(39999,1)
storage.bins[2]=bin(0,1)
storage.bins[2].coverage={ [0]={0,1,4,5},[1]={0,1},[2]={4,5} }
for _,ring in ipairs(storage.rings) do
  local id=math.floor(39999/ring.secs)-1
  ring.bins[1]=bin(id,ring.secs)
end
storage.stat_last={ [1]={[key]={i=900,o=800}}, [2]={[key]={i=600,o=200}} }
storage.machines={ [101]={u=101,s=1}, [202]={u=202,s=2} }
storage.mlist,storage.mcursor={101,202},2
local status_two={ [8]={kept={observed=1}} }
storage.machine_status={ [1]={ [9]={old={observed=1}} }, [2]=status_two }
local watch_two={ [key]={made=2, made_since=12} }
storage.ui={ [1]={bal_watches={ [1]={[key]={made=1}}, [2]=watch_two }},
  [8]={bal_watches={ [1]={[key]={empty=10}} }} }
storage.stock={ {tick=10,s={ [1]={[key]=400}, [2]={[key]=10} }} }
local function chest(unit,surface,count)
  return {valid=true,unit_number=unit,type="container",surface={index=surface},force=game.forces.player,
    get_inventory=function()return {valid=true,get_contents=function()return {{name="iron-plate",count=count}} end}end}
end
storage.chest_stock={list={1,2,3,4,5},entities={ [1]=chest(1,1,99),[2]=chest(2,2,10),[3]=chest(3,1,99),
  [4]=chest(4,2,7),[5]=chest(5,1,99) },next_tick=0,
  batch={start=100,cursor=3,limit=4,s={ [1]={[key]=99}, [2]={[key]=10} },reads=2} }
local before={}
for _,period in ipairs({3600,36000}) do
  local removed,seconds=Sampler.rates(1,period)
  assert(seconds>0 and removed.nodes[key] and removed.recipes.old,"deleted-surface fixture has no retained history")
  local other,duration=Sampler.rates(2,period)
  before[period]={prod=other.nodes[key].prod,cons=other.nodes[key].cons,cps=other.recipes.kept.cps,seconds=duration}
end
assert(type(Sampler.on_surface_deleted)=="function","surface deletion must purge retained sampler state")
Sampler.on_surface_deleted(1)
assert(storage.stat_last[1]==nil and storage.stat_last[2][key].i==600)
assert(#storage.bins[2].coverage[0]==2 and storage.bins[2].coverage[0][1]==4 and storage.bins[2].coverage[0][2]==5,
  "combined coverage must drop intervals belonging only to the deleted surface")
assert(storage.machines[101]==nil and storage.machines[202] and #storage.mlist==1 and storage.mlist[1]==202)
assert(storage.machine_status[1]==nil and storage.machine_status[2]==status_two)
assert(Watch.get(storage.ui[1],1,key)==nil and storage.ui[1].bal_watches[2]==watch_two
  and not (storage.ui[8].bal_watches and storage.ui[8].bal_watches[1]),"purge every player's watch for only the deleted surface")
assert(storage.stock[1].s[1]==nil and storage.stock[1].s[2][key]==10)
assert(#storage.chest_stock.list==2 and storage.chest_stock.list[1]==2 and storage.chest_stock.list[2]==4
  and storage.chest_stock.batch.cursor==2 and storage.chest_stock.batch.limit==2
  and storage.chest_stock.batch.s[1]==nil,"surface deletion must preserve the in-flight scan cursor and deferred boundary")
for _,period in ipairs({3600,36000}) do
  local removed,seconds=Sampler.rates(1,period)
  assert(seconds==0 and next(removed.nodes)==nil and next(removed.recipes)==nil,"replacement surface inherited old history")
  local other,duration=Sampler.rates(2,period);local expected=before[period]
  assert(duration==expected.seconds and other.nodes[key].prod==expected.prod and other.nodes[key].cons==expected.cons
    and other.recipes.kept.cps==expected.cps,"surface deletion changed another surface's rates")
end
-- The pre-deletion handler runs while the old surface still exists; remove it
-- before resuming the partial scan so it cannot be rediscovered.
game.surfaces={{index=2,find_entities_filtered=function()return {} end}}
defines={inventory={chest=1}}
ChestStock.tick(101)
assert(Sampler.stock(2)[key].count==17 and not Sampler.stock_known(1),"resumed scan double-counted or republished deleted stock")
-- Simulate the engine reusing the deleted index. Its first cumulative sample is
-- a fresh baseline, not a delta against the previous surface's counters.
local replacement={index=1,find_entities_filtered=function()return {} end}
game.surfaces={replacement}
game.forces.player.get_item_production_statistics=function()return {input_counts={["iron-plate"]=1000},output_counts={}} end
game.forces.player.get_fluid_production_statistics=function()return {input_counts={},output_counts={}} end
Sampler.on_stats(game.tick)
local slot=math.floor(game.tick/60)%storage.nbins+1
assert(storage.bins[slot].stat[1][key]==nil,"replacement surface's lifetime totals became new production")
print("SURFACE LIFECYCLE PASS: fine/coarse history, baselines, machine/status/stock registries, active scans, all-player watches and index reuse")
