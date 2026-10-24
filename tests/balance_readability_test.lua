local SK, V, P = TREQ("scripts.sankey_ui"), TREQ("scripts.view"), TREQ("shared.palette")
local player = game.players[1]
local c = player.gui.screen.add{type="flow", name="balance_readability_test"}
local function find(e, action, key)
  if e.tags.ssk_sk==action and (not key or e.tags.key==key) then return e end
  for _, child in ipairs(e.children) do local hit=find(child,action,key); if hit then return hit end end
end
local function click(e, us, shift) return SK.on_click({element=e,player_index=1,shift=shift},us) end
local us={view="focus",neighborhood=true,focus="item/electronic-circuit",period=600,
  renderer="poly",input_depth=2,heights="sqrt",canvas_w=1200,settings_open=true} -- Chart settings hold Unpin, Colors and Center
SK.fill(player,c,us,1200,800,true)
local L=V.build(player,us,1200,800)
assert(L.content_w<=1200 and L.content_h<=800, "small chain should fit without shrinking icons")
assert(c.ssk_sp.last_scroll_target, "Balance must center through the native scroll API")
local tops={}
for k,n in pairs(L.nodes) do
  tops[k]=n.top
  assert(n.top>=0 and n.y+n.h<=L.content_h, "node/header outside fitted content")
  assert(n.color==P.material(k), "material colors must not depend on node order")
end
local st=storage.sk_render["1:focus"]
assert(st.quiet and st.selected==nil and #st.ribbons>0)
for _,r in ipairs(st.ribbons) do
  assert(r.color==P.material(r.to), "default ribbon must use destination color")
  local tint=P.tint(P.muted(r.color))
  assert(math.abs(r.ro.color.r-tint.r)<0.0001, "idle ribbon must be subdued")
end
local neighbor="item/iron-plate#input"
assert(click(find(c,"node",neighbor),us,true)=="rebuild")
assert(us.pinned==neighbor and us.focus=="item/electronic-circuit", "pinning must retain focus")
SK.fill(player,c,us,1200,800,false)
assert(storage.sk_render["1:focus"].selected==neighbor)
SK.on_hover({element=find(c,"node",us.focus),player_index=1},true)
SK.on_hover({element=find(c,"node",us.focus),player_index=1},false)
assert(storage.sk_render["1:focus"].selected==neighbor, "hover leave must retain pinned chain")
local next_layout=V.build(player,us,1200,800)
for k,n in pairs(next_layout.nodes) do assert(n.top==tops[k], "unchanged live data must not move nodes") end
click(find(c,"unpin"),us)
assert(not us.pinned)
local colors=find(c,"balance_colors"); colors.selected_index=2
SK.on_selection({element=colors,player_index=1},us)
SK.fill(player,c,us,1200,800,false)
for _,r in ipairs(storage.sk_render["1:focus"].ribbons) do assert(r.color==P.material(r.from)) end
click(find(c,"center_selection"),us)
assert(us.center_pending)
SK.fill(player,c,us,1200,800,false)
assert(not us.center_pending and c.ssk_sp.last_scroll_target)
us.zoom=2
click(find(c,"zoom_fit"),us)
assert(us.zoom==1 and us.layout_snapshot==nil and us.center_pending)
c.destroy(); TREQ("scripts.canvas").clear(player.index)
print("BALANCE READABILITY OK: fit, centering, stable colors/layout, destination/source ribbons and pinning")
