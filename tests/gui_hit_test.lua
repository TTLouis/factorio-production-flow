local Check=dofile(TESTDIR.."/development/gui_interaction_checks.lua")
local SK=TREQ("scripts.sankey_ui")
local player=game.players[1]
local c=player.gui.screen.add{type="flow",name="ssk_hit_regression",direction="vertical"}
local function find(e,name)
  if e.name==name then return e end
  for _,child in ipairs(e.children) do local f=find(child,name);if f then return f end end
end
for _,scale in ipairs({1,1.25,1.5}) do
  for _,renderer in ipairs({"poly","sprites"}) do
    for _,tab in ipairs({"balance","focus","sankey"}) do
      local us={view=tab=="sankey" and "detail" or "focus",focus="item/iron-plate",neighborhood=tab=="balance",
        focus_steps=2,layout="clean",renderer=renderer,period=0,preset="all",heights="sqrt",lines="curves",show_labels=true}
      SK.fill(player,c,us,1000,700,true)
      local canvas=assert(find(c,"ssk_canvas"))
      local result=Check.inspect(canvas,scale)
      Check.assert_clear(result)
      local layout=TREQ("scripts.view").build(player,us,1000,700)
      local stubs=0
      for _,node in pairs(layout.nodes) do
        if node.stub_in>0 then stubs=stubs+1 end
        if node.stub_out>0 then stubs=stubs+1 end
      end
      assert(result.stub_targets==stubs,"Every visible source/use stub needs a native tooltip in both renderers")
    end
  end
end
c.destroy()
TREQ("scripts.canvas").clear(player.index)
print("GUI HIT MODEL OK: three tabs, both renderers, 100/125/150% geometry and native event flags")
