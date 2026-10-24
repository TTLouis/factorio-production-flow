local UI,SK,V=TREQ("scripts.ui"),TREQ("scripts.sankey_ui"),TREQ("scripts.view")
local p=game.players[1]
local saved=storage.ui[1]
local function find(e,action)
  if e.tags.ssk_sk==action then return e end
  for _,c in ipairs(e.children) do local x=find(c,action); if x then return x end end
end
local copper_preset=false
for _,preset in ipairs(V.presets()) do if preset.id=="roots:item/copper-plate" then copper_preset=preset.name=="Copper chain" end end
assert(copper_preset,"copper-chain filtering must identify itself in the preset picker")
local defaults={}; SK.defaults(defaults)
assert(defaults.view=="detail","new charts must use material names")
storage.ui[1]={tab_id="sankey",view="overview",readability_defaults=true,collapsed={plates=true}}
UI.open(p)
local us=storage.ui[1]
assert(us.view=="detail" and next(us.collapsed)==nil,"old grouped default must migrate once")
local chart=V.build(p,us,us.canvas_w,us.canvas_h)
for _,n in pairs(chart.nodes) do assert(n.kind~="group","plain view must not replace materials with categories") end
local picker=find(p.gui.screen.ssk_main,"view")
assert(picker.selected_index==2 and picker.items[1]:find("unfinished"),"grouping must be optional and marked unfinished")
picker.selected_index=1
UI.on_selection({player_index=1,element=picker})
UI.open(p)
assert(us.view=="overview","explicit grouping choice should survive reopening")
UI.close(p);storage.ui[1]=saved;UI.open(p)
print("PLAIN NAMES OK: material defaults, one-time migration and optional unfinished grouping")
