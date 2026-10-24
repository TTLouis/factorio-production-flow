local SK,V,P=TREQ("scripts.sankey_ui"),TREQ("scripts.view"),TREQ("shared.palette")
local player=game.players[1]
local c=player.gui.screen.add{type="flow",name="full_readability_test"}
local function find(e,action,key)
  if e.tags.ssk_sk==action and (not key or e.tags.key==key) then return e end
  for _,child in ipairs(e.children) do local hit=find(child,action,key); if hit then return hit end end
end
local function event(e) return {player_index=1,element=e} end
local function find_rate(e,key)
  if e.tags.ssk_rate==key then return e end
  for _,child in ipairs(e.children) do local hit=find_rate(child,key); if hit then return hit end end
end
for _,renderer in ipairs({"poly","sprites"}) do
  local us={view="detail",layout="clean",lines="curves",heights="sqrt",renderer=renderer,
    period=600,canvas_w=1600,settings_open=true} -- Unpin and Colors live in Chart settings
  SK.fill(player,c,us,1600,850,true)
  local L=V.build(player,us,1600,850)
  local before={}
  for k,n in pairs(L.nodes) do before[k]={n.top,n.x} end
  local segments=0
  for _,sg in ipairs(L.segments or {}) do if sg.a.kind=="via" or sg.b.kind=="via" then segments=segments+1 end end
  assert(segments>0,"fixture must test a ribbon across intermediate columns")
  for _,r in ipairs(storage.sk_render[1].ribbons) do
    assert(r.color==P.material(r.to),"every segment must use the logical destination color")
    if r.ro then assert(math.abs(r.ro.color.r-P.tint(P.muted(r.color)).r)<1e-8) end
  end
  assert(SK.on_click(event(find(c,"node","item/electronic-circuit")),us)=="rebuild")
  SK.fill(player,c,us,1600,850,false)
  assert(storage.sk_render[1].selected=="item/electronic-circuit")
  local node=find(c,"node","item/plastic-bar")
  SK.on_hover(event(node),true); SK.on_hover(event(node),false)
  assert(storage.sk_render[1].selected==us.sel)
  SK.on_click(event(find(c,"center_selection")),us)
  SK.fill(player,c,us,1600,850,false)
  assert(c.ssk_sp.last_scroll_target and not us.center_pending)
  L=V.build(player,us,1600,850)
  for k,n in pairs(L.nodes) do assert(n.top==before[k][1] and n.x==before[k][2],"pin/center must not reflow") end
  SK.on_click(event(find(c,"unpin")),us); assert(us.sel==nil)
  local colors=find(c,"balance_colors"); colors.selected_index=2
  SK.on_selection(event(colors),us); SK.fill(player,c,us,1600,850,false)
  for _,r in ipairs(storage.sk_render[1].ribbons) do assert(r.color==P.material(r.from)) end
end
-- Regression: dense columns must not fall back to scale=1 and giant ribbons.
local us={view="detail",layout="clean",lines="curves",heights="linear",period=600}
SK.defaults(us)
local dense=V.build(player,us,900,180)
local slots={}
for k,n in pairs(dense.nodes) do slots[k]=n end
for _,sg in ipairs(dense.segments) do slots[sg.a.key]=sg.a; slots[sg.b.key]=sg.b end
local minimum,actual={},{}
for _,n in pairs(slots) do
  local h=dense.min_t
  if n.kind~="via" then
    local tin=(#n.ins+(n.w_stub_in>0 and 1 or 0))*dense.min_t
    local tout=(#n.outs+(n.w_stub_out>0 and 1 or 0))*dense.min_t
    h=V.NODE_HEAD+math.max(V.F_BAR_MIN,tin,tout)
  end
  minimum[n.ci]=(minimum[n.ci] or -V.F_GAP)+h+V.F_GAP
  actual[n.ci]=(actual[n.ci] or -V.F_GAP)+n.slot+V.F_GAP
end
local target=180-V.PAD_TOP-V.PAD_BOTTOM
for _,h in pairs(minimum) do target=math.max(target,h) end
for _,h in pairs(actual) do assert(h<=target+0.02,"dense fit enlarged columns beyond their readable minimum") end
for _,col in ipairs(dense.cols) do
  table.sort(col,function(a,b) return a.top<b.top end)
  local previous=-1e9
  for _,n in ipairs(col) do
    assert(n.top>=V.PAD_TOP-0.01 and n.top>=previous-0.01)
    assert(n.y+n.h<=dense.content_h+0.01)
    previous=n.top+n.slot+V.F_GAP
  end
end
-- Balance uses report selected material consumed, including multi-output recipes.
local N=TREQ("scripts.neighborhood")
local nodes={ ["fluid/water"]={kind="fluid",prod=100,cons=80},
  ["item/concrete"]={kind="item",prod=20,cons=19},
  ["recipe/oil"]={kind="recipe"},["fluid/heavy-oil"]={kind="fluid"} }
local aliases=N.build(nodes,{{from="fluid/water",to="item/concrete",rate=35},
  {from="fluid/water",to="recipe/oil",rate=45},{from="recipe/oil",to="fluid/heavy-oil",rate=30}},
  {residuals={}},"fluid/water",1)
assert(aliases["item/concrete#use"].selected_usage==35 and aliases["item/concrete#use"].prod==20)
assert(aliases["recipe/oil#use"].selected_usage==45)
for _,focus in ipairs({"item/iron-plate","fluid/petroleum-gas"}) do
local fx={view="focus",neighborhood=true,focus=focus,period=600,renderer="poly",show_labels=true}
SK.fill(player,c,fx,900,700,true)
local material=V.build(player,fx,900,700)
local checked=0
for k,n in pairs(material.nodes) do
  if n.selected_usage then
    local target=find(c,"node",k)
    assert(target.tooltip[9]==" consumed", "consumer tooltip must identify selected material usage")
    assert(target.tooltip[6]:find(focus:sub(1,5)=="fluid" and "fluid/s" or "items/s",1,true))
    assert(find_rate(c,k).caption==target.tooltip[6],"visible uses label must match selected-material consumption")
    if n.kind~="recipe" then assert(target.tooltip[10]:find("Consumer production:",1,true)) end
    checked=checked+1
  end
end
assert(checked>0)
end
c.destroy(); TREQ("scripts.canvas").clear(player.index)
print("FULL READABILITY OK: logical ribbon colors, fit bounds, stable pin/center and selected-material usage")
