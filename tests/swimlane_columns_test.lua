local Graph = require("scripts.graph")
local Sampler = require("scripts.sampler")
local View = require("scripts.view")
script={active_mods={base="2.1.24"}}
settings={global={ ["ssk-window-seconds"]={value=60}, ["ssk-stock-scan-minutes"]={value=5} }}
local surface={index=1,name="nauvis",valid=true}
local player={index=1,surface=surface,force={index=1},mod_settings={ ["ssk-min-ribbon-px"]={value=6},["ssk-fluid-scale"]={value=.001} }}
game={tick=36000,surfaces={surface},forces={player=player.force}}
prototypes={item=setmetatable({}, {__index=function(_,name)return {name=name} end}),
  fluid=setmetatable({}, {__index=function(_,name)return {name=name} end}),technology={},get_entity_filtered=function()return {} end,
  recipe={ ["sulfuric-acid"]={name="sulfuric-acid",categories={"chemistry"},energy=1,enabled=true,
    ingredients={ {type="fluid",name="water",amount=100},{type="item",name="iron-plate",amount=1},{type="item",name="sulfur",amount=5} },
    products={ {type="fluid",name="sulfuric-acid",amount=50} }} }}
storage={}
Graph.build()
-- Import sulfur and iron: their earlier local production chains are absent.
-- They retain their technology era, while raw water starts in an earlier tier.
storage.graph.nodes["fluid/water"].era=0
storage.graph.nodes["item/iron-plate"].era=1
storage.graph.nodes["item/sulfur"].era=1
storage.graph.nodes["fluid/sulfuric-acid"].era=1
Sampler.init()
Sampler.rates=function()return {recipes={ ["sulfuric-acid"]={cps=1,normal_cps=1} },nodes={
  ["fluid/water"]={prod=100,cons=100},["item/iron-plate"]={prod=1,cons=1},
  ["item/sulfur"]={prod=5,cons=5},["fluid/sulfuric-acid"]={prod=50,cons=0} }},600 end
for _,tier_mode in ipairs({"tech","depth"}) do
  for _,split in ipairs({true,false}) do
    local us={view="detail",layout="lanes",tier_mode=tier_mode,split_raw=split,lines="curves",heights="sqrt",period=600,preset="all",
      hidden={},collapsed={},pos={},gpos={},lpos={}}
    local layout=View.build(player,us,1200,800)
    assert(#layout.links==3 and layout.nodes["fluid/water"] and layout.nodes["fluid/sulfuric-acid"],"partial-import acid chain must retain every physical input")
    assert(#layout.cols==#layout.col_tiers and #layout.cols==#layout.col_x,"column arrays and tier labels must remain aligned")
    for ci,col in ipairs(layout.cols) do
      assert(#col>0,"split_raw left an empty swimlane column")
      for _,node in ipairs(col) do assert(node.ci==ci and node.x==layout.col_x[ci],"compacted node column/position mapping is inconsistent") end
    end
    for _,link in ipairs(layout.links) do assert(link.a.ci<link.b.ci,"column compaction reversed a material flow") end
  end
end
print("SWIMLANE COLUMNS PASS: water → acid with imported sulfur/iron, tech/depth tiers and split-raw on/off")
