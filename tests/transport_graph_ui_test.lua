-- External supply annotates the material; exports are ordinary linked nodes.
local Transport=TREQ("scripts.transport_flows")
local View=TREQ("scripts.view")
local SK=TREQ("scripts.sankey_ui")
local player=game.players[1]
local original=Transport.query
local unknown_item=rawget(prototypes.item,"transport-only-fixture")
local export_item=rawget(prototypes.item,"export-only-fixture")
prototypes.item["transport-only-fixture"]={name="transport-only-fixture",localised_name="Unknown fixture"}
prototypes.item["export-only-fixture"]={name="export-only-fixture",localised_name="Export fixture"}
local function config(neighborhood,focus)
  return {view=focus and "focus" or "detail",neighborhood=neighborhood,focus=focus,focus_steps=2,
    input_depth=1,period=600,renderer="poly",heights="linear",split_raw=false}
end
local function empty() return {provider="se",materials={}} end
local function evidence(key,sent,received,sent_rate,received_rate,direction,remote)
  return {activity=true,sent=sent,received=received,sent_rate=sent_rate,received_rate=received_rate,
    sent_known=sent~=nil,received_known=received~=nil,received_partial=received==nil,
    routes={{method="rocket",remote_name=remote}},
    history={provider="se",surface_index=player.surface.index,material=key:sub(6),direction=direction}}
end
local function fixture(force,surface,tick,seconds)
  assert(force==player.force and surface==player.surface and tick==game.tick and seconds==600,"Wrong transport scope/window")
  return {provider="se",surface_index=surface.index,materials={
    ["item/iron-plate"]={material="iron-plate",provider="se",
      imports=evidence("item/iron-plate",7200,6000,12,10,"imports","Orbit fixture"),
      exports=evidence("item/iron-plate",2400,1800,4,3,"exports","Moon fixture")},
    ["item/transport-only-fixture"]={material="transport-only-fixture",provider="se",
      imports=evidence("item/transport-only-fixture",900,nil,1.5,nil,"imports","Unknown fixture"),exports={activity=false}},
    ["item/export-only-fixture"]={material="export-only-fixture",provider="se",imports={activity=false},
      exports=evidence("item/export-only-fixture",3000,nil,5,nil,"exports","Export moon")}}}
end
local function local_rates(layout)
  local result={}
  for _,link in ipairs(layout.links) do if not link.transport then result[link.from..">"..link.to]=link.rate end end
  return result
end
local function export_for(layout,key)
  for _,node in pairs(layout.nodes) do if node.transport and node.transport.material==key then return node end end
end
for _,scope in ipairs({{false,nil},{false,"item/iron-plate"},{true,"item/iron-plate"}}) do
  local us=config(scope[1],scope[2]);SK.defaults(us)
  Transport.query=empty
  local baseline=View.build(player,us,1000,700)
  local before=local_rates(baseline)
  Transport.query=fixture
  local layout=View.build(player,us,1000,700)
  local material=assert(layout.nodes["item/iron-plate"])
  local old=assert(baseline.nodes["item/iron-plate"])
  assert(material.prod==old.prod and material.cons==old.cons,"Transport changed measured production/consumption")
  assert(material.stub_in==old.stub_in and material.stub_out==old.stub_out,"Transport was netted into local stubs")
  local after=local_rates(layout)
  for key,rate in pairs(before) do assert(after[key]==rate,"Normal recipe edge changed: "..key) end
  for key,rate in pairs(after) do assert(before[key]==rate,"Normal recipe edge invented: "..key) end
  assert(material.external_imports[1].evidence.received_rate==10,"External supply missing from the existing material")
  assert(not layout.transport_columns,"Dedicated transport columns returned")
  for key,node in pairs(layout.nodes) do
    assert(not key:find("transport/imports/",1,true),"Imports must not create separate nodes")
    if node.transport then
      assert(node.transport.direction=="exports" and #node.ins>0 and #node.outs==0,"Unlinked/invalid export node")
      assert(node.lane==material.lane or node.transport.material~="item/iron-plate","Export lives in a separate transport lane")
    end
  end
  local outgoing=assert(export_for(layout,"item/iron-plate"))
  assert(outgoing.ci>material.ci and outgoing.transport.rate==4,"Export used counterpart receipt rate")
  assert(outgoing.ins[1].a==material and outgoing.ins[1].rate==4)
  assert(not layout.nodes["item/transport-only-fixture"],"Unquantified disconnected entry appeared")
  if scope[1] then
    assert(#layout.cols==3 and outgoing.ci==3,"Export did not share the normal Uses column")
  elseif not scope[2] then
    assert(layout.nodes["item/export-only-fixture"] and export_for(layout,"item/export-only-fixture"),"Observed export-only chain lost")
  end
end
local hidden=config(false);SK.defaults(hidden);hidden.hidden["item/iron-plate"]=true
assert(not export_for(View.build(player,hidden,1000,700),"item/iron-plate"),"Hidden material left its export behind")
local collapsed=config(false);SK.defaults(collapsed)
local group=TREQ("scripts.groups").of(player.index,"item/iron-plate")
collapsed.collapsed[group]=true
local grouped=View.build(player,collapsed,1000,700)
local export=assert(export_for(grouped,"item/iron-plate"))
assert(export.ins[1].a.kind=="group" and export.ins[1].rate==4,"Collapsed material lost exact export")
assert(export.ins[1].a.external_imports,"Collapsed material lost external-supply hover")
local overview=config(false);overview.view="overview";SK.defaults(overview)
assert(export_for(View.build(player,overview,1000,700),"item/iron-plate"),"Overview swallowed export into its supply group")
local split=config(false);split.split_raw=true;SK.defaults(split)
assert(View.build(player,split,1000,700).nodes["item/iron-plate"],"Transport duplicated the material into raw supply copies")
local limited=config(false);SK.defaults(limited);limited.top_n=1
local top=View.build(player,limited,1000,700)
for _,n in pairs(top.nodes) do if n.transport then assert(#n.ins>0,"Filtered export became disconnected") end end
for _,width in ipairs({600,940,1000,1200}) do
  local us=config(true,"item/iron-plate");SK.defaults(us)
  local layout=View.build(player,us,width,700)
  assert(#layout.cols==3 and layout.content_w==width,"Ordinary three-column geometry changed")
  assert(layout.nodes["item/iron-plate"].x==math.floor(width/2-View.NODE_W/2),"Selected material is not centered")
end
Transport.query=empty
local deep=config(true,"item/electronic-circuit");deep.input_depth=4;SK.defaults(deep)
assert(View.build(player,deep,600,700).content_w>600,"Real upstream expansion lost scrolling")
Transport.query=fixture
local canvas=player.gui.screen.add{type="flow",name="ssk_transport_graph_fixture",direction="vertical"}
local function walk(e,fn) fn(e);for _,child in ipairs(e.children) do walk(child,fn) end end
for _,renderer in ipairs({"poly","sprite"}) do
  local us=config(true,"item/iron-plate");us.renderer=renderer
  SK.fill(player,canvas,us,1000,700,true)
  local exports,supply=0,0
  walk(canvas,function(e)
    local tags=e.tags or {}
    assert(not tags.ssk_transport_column,"Transport header reappeared")
    if e.caption then
      local caption=LOC(e.caption)
      assert(not caption:find("Orbit fixture",1,true) and not caption:find("Moon fixture",1,true),"Route detail escaped hover")
    end
    if tags.ssk_ui=="transport_history" then
      exports=exports+1
      assert(tags.direction=="exports" and tags.material=="iron-plate" and tags.surface_index==player.surface.index)
      local text=LOC(e.tooltip)
      assert(text:find("2400",1,true) and text:find("1800",1,true) and text:find("Moon fixture",1,true))
      assert(SK.on_click({element=e,player_index=player.index},us)==nil,"Export click entered material navigation")
    elseif tags.ssk_sk=="node" and tags.key=="item/iron-plate" and e.tooltip then
      supply=supply+1
      local text=LOC(e.tooltip)
      assert(text:find("External supply",1,true) and text:find("7200",1,true) and text:find("6000",1,true)
        and text:find("Orbit fixture",1,true) and text:find("Cargo rocket",1,true),"Supply/method/surface missing from material hover")
    end
  end)
  assert(exports>2 and supply>=2,"Normal nodes lost their tooltips/click targets")
end
-- A Uses node that also receives external supply keeps the selected-material
-- lines in place (Space Age save regression: the hover was nested instead).
do
  local us=config(true,"item/iron-plate");SK.defaults(us)
  local use_key
  for key,node in pairs(View.build(player,us,1000,700).nodes) do
    if key:match("^item/.+#use$") and not node.transport then use_key=node.group_key break end
  end
  assert(use_key,"Fixture has no Uses material")
  Transport.query=function(...)
    local result=fixture(...)
    result.materials[use_key]={material=use_key:sub(6),provider="se",exports={activity=false},
      imports=evidence(use_key,600,500,1,0.8,"imports","Orbit fixture")}
    return result
  end
  SK.fill(player,canvas,us,1000,700,true)
  local checked=0
  walk(canvas,function(e)
    local tags=e.tags or {}
    if tags.ssk_sk=="node" and tags.key==use_key.."#use" and e.tooltip and LOC(e.tooltip):find("External supply",1,true) then
      checked=checked+1
      assert(LOC(e.tooltip[7]):find(" consumed",1,true),"External supply displaced the selected-material line")
      assert(LOC(e.tooltip[6]):find("items/s",1,true),"External supply displaced the usage rate")
    end
  end)
  assert(checked>0,"Uses node lost its external-supply hover")
  Transport.query=fixture
end
canvas.destroy()
Transport.query=original
prototypes.item["transport-only-fixture"]=unknown_item
prototypes.item["export-only-fixture"]=export_item
print("TRANSPORT GRAPH UI PASS: merged external-supply hover, ordinary linked exports, unchanged local accounting/layout, filters and History targets")
