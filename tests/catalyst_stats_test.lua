local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")
local View = require("scripts.view")
local u235, u238 = "item/uranium-235", "item/uranium-238"
script = { active_mods={base="2.1.24"} }
settings = { global={ ["ssk-window-seconds"]={value=60}, ["ssk-stock-scan-minutes"]={value=5} } }
local surface={index=1,name="nauvis",valid=true}
local player={index=1,surface=surface,force={index=1},mod_settings={ ["ssk-min-ribbon-px"]={value=6},["ssk-fluid-scale"]={value=.001} }}
game={tick=36000,surfaces={surface},forces={player=player.force}}
prototypes={item=setmetatable({}, {__index=function(_,name)return {name=name} end}),fluid={},technology={},
  get_entity_filtered=function()return {} end}
local function recipe(ignored_in, ignored_out)
  return {name="kovarex-enrichment-process",categories={"centrifuging"},energy=60,enabled=true,
    ingredients={ {type="item",name="uranium-235",amount=40,ignored_by_stats=ignored_in},
      {type="item",name="uranium-238",amount=5,ignored_by_stats=2} },
    products={ {type="item",name="uranium-235",amount=41,ignored_by_productivity=40,ignored_by_stats=ignored_out},
      {type="item",name="uranium-238",amount=2,ignored_by_productivity=2,ignored_by_stats=2} }}
end
local function run(ignored_in, ignored_out, bonus)
  bonus = bonus or 0
  storage={}
  prototypes.recipe={ ["kovarex-enrichment-process"]=recipe(ignored_in,ignored_out) }
  local graph=Graph.build()
  Sampler.init()
  Sampler.rates=function()return {recipes={ ["kovarex-enrichment-process"]={cps=1+bonus,normal_cps=1} },
    nodes={ [u235]={prod=41-ignored_out+bonus,cons=40-ignored_in},[u238]={prod=0,cons=3} }},600 end
  local function build(hidden)
    local us={view="detail",layout="clean",tier_mode="depth",lines="curves",heights="sqrt",period=600,preset="all",
      hidden=hidden or {},collapsed={},pos={},gpos={},lpos={}}
    return View.build(player,us,1200,800)
  end
  local full=build()
  assert(full.nodes[u235] and full.nodes[u238] and #full.links==1,"Kovarex must draw the net U-238 → U-235 flow")
  local filtered=build({[u238]=true})
  assert(math.abs(filtered.nodes[u235].stub_in-(1+bonus))<1e-8,
    "filtered Kovarex must retain its net U-235 source after ignored_by_stats excludes the catalyst")
  assert(filtered.nodes[u235].stub_out==0,"Kovarex catalyst must not become an external U-235 use")
  local used=build({[u235]=true})
  assert(math.abs(used.nodes[u238].stub_out-3)<1e-8,
    "filtering the product must expose all three net U-238 uses")
  return graph
end
run(0,0) -- Legacy/modded recipes whose statistics include the circulating catalyst.
local ignored=run(40,40)
assert(ignored.recipes["kovarex-enrichment-process"].ingredients[1].ignored_by_stats==40
  and ignored.recipes["kovarex-enrichment-process"].products[1].ignored_by_stats==40,"graph must retain ingredient and product statistics exclusions")
run(10,20) -- Ingredient and product exclusions need separate catalyst adjustments.
run(10,20,.5) -- Productivity adds only the eligible net product, not another catalyst batch.
print("CATALYST STATS PASS: gross/net statistics, separate ingredient/product exclusions, and filtered Kovarex source/use stubs")
