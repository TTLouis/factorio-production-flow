local Sampler = require("scripts.sampler")
local Canvas = require("scripts.canvas")
settings={global={ ["ssk-window-seconds"]={value=60}, ["ssk-stock-scan-minutes"]={value=5} }}
storage={}
local total, reads, surfaces = {}, {}, {}
for i=1,10 do surfaces[#surfaces+1]={index=i,name="factory-"..i};total[i]=0 end
surfaces[#surfaces+1]={index=99,name=Canvas.SURFACE}
local force={}
force.get_item_production_statistics=function(surface)
  reads[surface.index]=(reads[surface.index] or 0)+1
  return {input_counts=total[surface.index] and total[surface.index]>0 and {["water-barrel"]=total[surface.index]} or {},output_counts={}}
end
force.get_fluid_production_statistics=function(surface)
  reads[surface.index]=(reads[surface.index] or 0)+1
  return {input_counts={},output_counts={}}
end
game={tick=0,forces={player=force},surfaces=surfaces}
Sampler.init()
for second=1,120 do game.tick=second*60;Sampler.on_stats(game.tick) end
assert(reads[99]==nil and storage.stat_last[99]==nil,"the internal drawing surface must not collect factory statistics")
local empty=storage.empty_stat
assert(type(empty)=="table" and next(empty)==nil,"known-zero statistics need one save-stable empty sentinel")
local maps,entries={},0
for _,bin in pairs(storage.bins) do
  for _,map in pairs(bin.stat) do maps[map]=true;entries=entries+1 end
end
local distinct=0;for _ in pairs(maps) do distinct=distinct+1 end
assert(entries==1200 and distinct==1 and maps[empty],"all 1,200 fine-bin known-zero entries should share one empty map")
for index=1,10 do
  assert(reads[index]==240,"stat-only surfaces must retain both statistics reads every second")
  assert(Sampler.coverage(index,3600)==119,"known-zero coverage was lost on a surface without tracked machines")
end
-- A script, mining drill or offshore pump can change statistics on a surface
-- with no tracked crafting machines. Preserve the measurement and use COW.
total[1]=7;game.tick=121*60;Sampler.on_stats(game.tick)
local current=storage.bins[122]
assert(current.stat[1]~=empty and current.stat[1]["item/water-barrel"].i==7 and current.stat[2]==empty,
  "one positive delta must detach only its own bin/surface from the shared empty map")
assert(storage.bins[121].stat[1]==empty and next(empty)==nil,"new production contaminated earlier zero-history bins")
game.tick=122*60;Sampler.on_stats(game.tick)
local rates,seconds=Sampler.rates(1,3600)
assert(seconds==121 and math.abs(rates.nodes["item/water-barrel"].prod-7/121)<1e-12,
  "stat-only production must remain measurable after empty-map sharing")
assert(next(Sampler.rates(2,3600).nodes)==nil and Sampler.coverage(2,3600)==121,
  "another surface acquired production or lost zero coverage")
for _,ring in ipairs(storage.rings) do
  for _,bin in pairs(ring.bins) do
    if bin.stat[1] and bin.stat[1]["item/water-barrel"] then
      assert(bin.stat[1]~=empty,"coarse rollup mutated the shared empty sentinel")
    end
    assert(not bin.stat[2] or next(bin.stat[2])==nil,"rollup contaminated another surface's known-zero totals")
  end
end
local same=storage.empty_stat;Sampler.init()
assert(storage.empty_stat==same,"sampler init must preserve saved sentinel identity")
print("EMPTY STATS PASS: 1,200 known-zero fine entries share one map; COW/rollups isolated, stat-only coverage/rates preserved, internal canvas omitted")
