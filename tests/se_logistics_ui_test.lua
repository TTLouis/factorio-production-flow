local UI=TREQ("scripts.ui")
local Rockets=TREQ("scripts.se_rockets")
local Cannons=TREQ("scripts.se_cannons")
local Data=TREQ("scripts.se_transfer_data")
local Panels=TREQ("scripts.se_transfer_panels")
local SEView=TREQ("scripts.se_logistics_ui")
local player=game.players[1]
local us=storage.ui[1]
local saved={mods=script.active_mods,events=defines.events,controllers=defines.controllers,
  rockets=storage.se_rockets,cannons=storage.se_cannons,stock=storage.stock,basis=storage.stock_basis,
  player_valid=player.valid,controller=player.controller_type,force_valid=player.force.valid,force_index=player.force.index,
  surface_valid=player.surface.valid,surface=player.surface,surface_find=player.surface.find_entities_filtered,
  favs=us.bal_favs,tab=us.tab_id,scope=us.surface,period=us.period,state=us.se_logistics,remote=remote,game_force=game.forces.player}
local function find(e,predicate)
  if predicate(e) then return e end
  for _,c in ipairs(e.children or {}) do local hit=find(c,predicate);if hit then return hit end end
end
local function tagged(e,action,predicate)
  return find(e,function(c) return c.tags and c.tags.se_logistics==action and (not predicate or predicate(c.tags,c)) end)
end
local function shapes(plot,color)
  local result={}
  local function visit(e)
    if e.sprite=="ssk-plot-"..color then result[#result+1]=e end
    for _,child in ipairs(e.children) do visit(child) end
  end
  visit(plot)
  return result
end
local function click(e) return UI.on_click{element=assert(e),player_index=player.index} end
local function panel() return assert(player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_transfers.ssk_se_logistics) end
local function tab(index,view)
  local tabs=panel().se_tabs;tabs.selected_tab_index=index
  assert(UI.on_tab_changed{element=tabs,player_index=player.index})
  assert(us.se_logistics.view==view,"Transfers subtab state mismatch")
end
player.valid=true;player.controller_type=2;player.force.valid=true;player.force.index=1;player.surface.valid=true
game.forces.player=player.force
local origin=player.surface
local orbit={valid=true,index=501,name="SE Orbit"}
game.surfaces[501]=orbit;game.surfaces[orbit.name]=orbit
script.active_mods={["space-exploration"]="0.7.64"}
defines.events={se_on_cargo_rocket_launched=501,se_on_cargo_rocket_padless=502,on_script_trigger_effect=503}
defines.controllers={cutscene=1,character=2}
local entities={}
local function lookup(surface,f)
  if not f.name then return saved.surface_find(f) end
  local allowed={};for _,n in ipairs(type(f.name)=="table" and f.name or {f.name}) do allowed[n]=true end
  local out={}
  for _,e in ipairs(entities) do
    local p=f.position
    if e.valid and e.surface==surface and allowed[e.name] and (not f.force or f.force==e.force)
      and (not p or (e.position.x-p.x)^2+(e.position.y-p.y)^2<=(f.radius or 0)^2) then
      out[#out+1]=e;if f.limit and #out>=f.limit then break end
    end
  end
  return out
end
origin.find_entities_filtered=function(f) return lookup(origin,f) end
orbit.find_entities_filtered=function(f) return lookup(orbit,f) end
local function endpoint(unit,surface,name,x,y)
  local e={valid=true,unit_number=unit,name=name,surface=surface,force=player.force,position={x=x,y=y}}
  e.get_inventory=function() return {valid=true,get_contents=function() return {} end} end
  e.get_recipe=function() return nil end
  entities[#entities+1]=e;return e
end
remote={interfaces={["space-exploration"]={get_zone_from_surface_index=true,remote_view_start=true,remote_view_is_active=true}},
  call=function(_,method,args)
    if method=="get_zone_from_surface_index" then local s=game.surfaces[args.surface_index];return {name=s.name,surface_index=s.index} end
    if method=="remote_view_start" then player.surface=game.surfaces[args.zone_name];return end
    if method=="remote_view_is_active" then return true end
  end}
local function launch(unit,from,to,name,count)
  assert(Rockets.available(),"mock SE rocket provider unavailable")
  assert(player.force==game.forces.player,"mock player force diverged from game force")
  assert(type(game.tick)=="number" and from.valid and to.valid,"mock endpoint surface invalid")
  local sender=endpoint(unit,from,"se-rocket-launch-pad",unit/100,0)
  local receiver=endpoint(unit+100,to,"cargo-landing-pad",unit/100,20)
  Rockets.on_launch{tick=game.tick,unit_number=unit,force_name="player",launchpad=sender,
    zone_index=from.index,zone_name=from.name,destination_zone_index=to.index,destination_zone_name=to.name,
    landing_pad=receiver,launched_contents={{name=name,count=count,quality="normal"}}}
end
storage.se_rockets=nil;Rockets.init(game.tick-200)
storage.se_cannons=nil;Cannons.init(game.tick-200)
launch(40001,origin,orbit,"iron-plate",1000)
launch(40002,orbit,origin,"copper-plate",400)
local cannon=endpoint(41000,origin,"se-delivery-cannon",10,10)
Cannons.on_effect{effect_id=Cannons.EFFECT_ID,tick=game.tick,surface_index=origin.index,source_position={x=9.5,y=5}}
us.tab_id="transfers";us.surface=nil;us.period=600;us.se_logistics={view="flow"}
UI.open(player)
local window=player.gui.screen.ssk_main
assert(LOC(window.ssk_inner.ssk_tabs.children[9].caption)=="Transfers","SE main tab must remain Transfers")
assert(window.ssk_window_bar.ssk_surface_picker.visible,"SE Transfers lost global surface scope")
assert(panel().se_tabs and panel().se_tabs.se_flow and panel().se_tabs.se_items and panel().se_tabs.se_history)
assert(panel().se_tabs.se_flow.viewport.body.se_graph,"Flow is missing the standalone diagram")
-- Compact route cards replace the per-method cargo preview; the Flow switch's
-- Items grouping lists the observed cargo per route (asserted below).
assert(not find(panel().se_tabs.se_flow.viewport.body,function(e) return e.name=="cargo_preview" end),
  "Compact route cards must not keep the old per-method cargo preview")
-- The native subtab strip carries shared actions. Only Items needs a filter toolbar.
local main_tabs=window.ssk_inner.ssk_tabs
assert(main_tabs.content_transfers.style.left_padding==main_tabs.content_balance.style.left_padding
  and main_tabs.content_transfers.style.right_padding==main_tabs.content_balance.style.right_padding,
  "Transfers must use the same side insets as the main views")
assert(panel().se_tabs.style.top_margin==0)
for _,view in ipairs({"flow","items","history"}) do
  local frame=panel().se_tabs["se_"..view]
  assert(frame.style.padding==0)
  if view~="items" then
    assert(not frame.toolbar,"Flow and History should give the full panel height to their content")
  else
    assert(frame.toolbar.spec.style=="subheader_frame" and frame.toolbar.controls.style.height==40)
    assert(frame.toolbar.style.left_padding==12 and frame.toolbar.style.right_padding==12)
    assert(frame.toolbar.style.top_padding==8 and frame.toolbar.style.bottom_padding==8)
  end
  assert(frame.viewport.spec.style=="naked_scroll_pane" and frame.viewport.style.left_padding==12)
end
local heading=assert(panel().heading)
assert(heading.se_coverage and tagged(heading,"surface-jump"),"Shared controls should sit beside the subtabs")
for _,side in ipairs({"imports","exports"}) do
  local previous=tagged(panel().se_tabs.se_flow.viewport.body,"page",function(t) return t.side==side and t.delta==-1 end)
  local following=tagged(panel().se_tabs.se_flow.viewport.body,"page",function(t) return t.side==side and t.delta==1 end)
  assert(previous.enabled==false and following.enabled==false,"Single-page arrows must be disabled")
end
us.se_logistics.material="iron-plate"
UI.refresh(player,true)
assert(panel().heading==heading,"Live refresh rebuilt the shared heading")
assert(tagged(panel().se_tabs.se_flow.viewport.body,"history",function(t)return t.direction=="imports" end),
  "An Items material selection hid an unrelated incoming cargo route")
local q=Data.query(player.force,origin,game.tick,600,{material="iron-plate",timing="either"})
assert(#q.records==1 and q.records[1].sent[1].count==1000 and q.records[1].received==nil)
local card=assert(find(panel().se_tabs.se_flow.viewport.body,function(e) return e.name=="se_route_card" end),"Flow has no route card")
local head,first=card.rows.children[1],card.rows.children[2]
assert(card.heading.route_name and card.heading.route_history.tags.se_logistics=="history"
  and card.heading.route_history.tags.method==nil and head==card.rows.columns and first==card.rows.method_1
  and LOC(head.children[3].caption)=="Sent" and LOC(head.children[4].caption)=="Received",
  "Route cards need one History action in the name strip and a Sent/Received heading over the method rows")
-- The Flow switch regroups each surface card's rows by item; surfaces stay the first level.
local function flow_body() return panel().se_tabs.se_flow.viewport.body end
local function grouping() return assert(find(flow_body(),function(e) return e.name=="se_group" end),"Flow has no grouping switch") end
assert(grouping().spec.type=="switch" and grouping().spec.allow_none_state==false and grouping().switch_state=="left"
  and LOC(grouping().spec.left_label_caption)=="Transport" and LOC(grouping().spec.right_label_caption)=="Items")
us.se_logistics.exports_page=2
grouping().switch_state="right"
assert(UI.on_switch{element=grouping(),player_index=player.index} and us.se_logistics.group=="items"
  and us.se_logistics.exports_page==1,"Switching grouping must select Items and return to the first page")
assert(grouping().switch_state=="right","Rebuilt Flow lost the Items switch state")
local export_card=assert(find(flow_body(),function(e)
  return e.name=="se_route_card" and e.rows.item_1 and e.rows.item_1.children[1].sprite=="item/iron-plate" end),"Items mode has no iron-plate row")
local item_row=export_card.rows.item_1
assert(LOC(export_card.rows.columns.children[1].caption)=="Items" and not export_card.rows.method_1 and not export_card.rows.item_2,
  "Items mode lists one row per item under an Items heading")
assert(item_row.children[1].spec.type=="sprite-button" and item_row.children[4].caption=="1,000" and item_row.children[5].caption=="—",
  "Item rows show the known sent amount and an unknown receipt")
local item_history=assert(tagged(flow_body(),"history",function(t) return t.material=="iron-plate" and t.quality=="normal" and t.direction=="exports" end),
  "Item ribbons must open History for that item")
assert(export_card.heading.route_history.tags.material==nil,"The surface strip still opens all items")
grouping().switch_state="left"
assert(UI.on_switch{element=grouping(),player_index=player.index} and us.se_logistics.group=="transport")
card=assert(find(flow_body(),function(e) return e.name=="se_route_card" end))
assert(card.rows.method_1 and not card.rows.item_1,"Transport mode must restore the method rows")
local route=assert(tagged(panel().se_tabs.se_flow.viewport.body,"history",function(t) return t.direction=="exports" end),"Flow route has no History action")
assert(click(route))
assert(us.se_logistics.view=="history" and us.se_logistics.material=="iron-plate")
assert(us.se_logistics.history.return_view=="flow" and us.se_logistics.history.route)
local hs=us.se_logistics.history
assert(#Panels.last_records(hs)==1 and Panels.last_records(hs)[1].sent[1].count==1000 and Panels.last_records(hs)[1].received==nil,"History fabricated or conflated a receipt")
local saved_route,saved_material,saved_method=hs.route,hs.material,hs.method
us.period=3600;UI.refresh(player)
assert(hs.route==saved_route and hs.material==saved_material and hs.method==saved_method,"Period change discarded route/material/method")
us.period=600;UI.refresh(player)
-- Unknown receipts produce no positive/blue amount bars. A departure remains
-- selectable on the same timeline and uses the exact sent amount.
local history_plot=panel().se_tabs.se_history.viewport.body.entity_history.main.se_history_layout.se_history_plot
local sent_bars,received_bars=#shapes(history_plot,"outgoing"),#shapes(history_plot,"incoming")
assert(sent_bars==1 and received_bars==0,"History turned an unknown receipt into a plotted amount")
local function axis_switch()
  return assert(find(panel().se_tabs.se_history,function(e) return e.tags.transfer_axis end))
end
local axis=axis_switch()
assert(axis.type=="switch" and axis.switch_state=="left" and not axis.allow_none_state)
UI.refresh(player,true)
assert(axis_switch()==axis and axis.valid,"Live refresh rebuilt the History axis switch")
axis.switch_state="right";assert(UI.on_switch{element=axis,player_index=1})
assert(hs.axis=="events" and hs.material==nil and #Panels.last_exchanges(hs)>0,"Route History must retain every manifest item")
assert(axis_switch()==axis and axis.switch_state=="right")
local exchange_hit=assert(tagged(panel().se_tabs.se_history,"panel-exchange"))
assert(click(exchange_hit) and hs.exchange,"Exchange click did not select its records")
axis=axis_switch();axis.switch_state="left"
assert(UI.on_switch{element=axis,player_index=1} and hs.axis=="time" and hs.exchange==nil)
-- The shared GUI mock predates this native LuaGuiElement method.
local history_scroll=assert(find(panel().se_tabs.se_history.viewport.body,function(e) return e.name=="se_history_log" end))
assert(axis.parent.spec.style=="subheader_frame" and axis.parent.style.height==38
  and history_scroll.parent.se_history_headers.spec.style=="repeated_subheader_frame")
local shipment=history_scroll.se_shipment_1.children[1]
assert(shipment.children[4].children[1].sprite=="item/iron-plate" and shipment.children[5].caption=="—",
  "The known sent manifest must preview cargo while an unknown receipt stays explicit")
if not history_scroll.scroll_to_top then
  history_scroll.scroll_to_top=function() history_scroll.last_scroll_target="top" end
end
local bucket=assert(tagged(panel().se_tabs.se_history,"panel-bucket"))
local selected_bucket=bucket.tags.bucket
assert(click(bucket) and hs.bucket==selected_bucket)
assert(click(tagged(panel().se_tabs.se_history,"panel-bucket-clear")) and hs.bucket==nil)
assert(click(tagged(panel().se_tabs.se_history,"panel-expand")))
assert(us.se_logistics.history.expanded==Panels.last_records(hs)[1].key,"History expansion lost shipment identity")
local manifests=history_scroll.se_shipment_1.manifest_detail.manifests
-- No subtitles or departure/outcome lines: the detail is one item/lost/received table.
local detail_frame=history_scroll.se_shipment_1.manifest_detail
assert(#detail_frame.children==1 and not manifests.sent and #manifests.received.children==1,
  "Expanded shipment must hold only its manifest table")
local sent=manifests.received.manifest
assert(sent.type=="table" and sent.column_count==1 and sent.children[1].name=="header_1")
assert(not sent.draw_vertical_lines,"A short manifest must not draw collapsed dividers for its empty columns")
local unmeasured=sent.children[2]
assert(LOC(unmeasured.children[1].caption):find("[item=iron-plate]",1,true) and unmeasured.received.caption=="—"
  and unmeasured.lost.caption=="—" and unmeasured.received.style.horizontal_align=="right"
  and LOC(unmeasured.tooltip):find("1000",1,true),"An unmeasured receipt must read unknown, never zero, and keep its sent amount")
local sender=assert(tagged(panel().se_tabs.se_history,"panel-jump",function(t) return t.side=="sender" end))
local receiver=assert(tagged(panel().se_tabs.se_history,"panel-jump",function(t) return t.side=="receiver" end))
assert(sender.enabled and receiver.enabled,"Known intended endpoints must expose native jump actions")
local log_headers=history_scroll.parent.se_history_headers.children[1].children
assert(LOC(log_headers[6].caption)=="Sender" and LOC(log_headers[7].caption)=="Receiver")
assert(log_headers[6].style.width==sender.parent.style.width and log_headers[7].style.width==receiver.parent.style.width,
  "Endpoint header and action widths must match")
-- An existing button must revalidate its saved endpoint when clicked.
local record=Panels.last_records(hs)[1];local old_surface=player.surface
record.sender.entity.valid=false
assert(click(sender) and UI.is_open(player) and player.surface==old_surface,"Stale jump closed or moved the player")
record.sender.entity.valid=true
UI.close(player);UI.open(player)
assert(us.se_logistics.view=="history" and us.se_logistics.history.expanded==record.key,"Reopening lost selected History detail")
assert(click(tagged(panel().se_tabs.se_history,"panel-return")))
assert(us.se_logistics.view=="flow" and us.se_logistics.material=="iron-plate","Return lost caller view or material")
-- Shipped-item membership, Balance table styling, shared favourites and History controls.
local ItemList=TREQ("scripts.transport_items_ui")
local recipe_names,recipe_items=ItemList.manifests({records={},from_tick=0,to_tick=game.tick},{method="cannon"},{cannons={{declared_payload={name="iron-plate",count_per_package=100}}}})
assert(#recipe_names==1 and recipe_items["iron-plate"].configured and recipe_items["iron-plate"].sent_unknown,
  "Configured cannon recipes must populate Items without inventing sent manifests")
assert(#ItemList.manifests({records={},from_tick=0,to_tick=game.tick},{method="rocket"},{cannons={{declared_payload={name="iron-plate"}}}})==0)
tab(2,"items")
local function items_root() return assert(panel().se_tabs.se_items.viewport.body.transport_items) end
local ir=items_root()
local stack=ir.list.box.viewport.stack
local headers=stack.header.columns.children
local cells=stack.rows.grid.children
assert(stack.header.spec.style=="ssk_balance_header" and stack.rows.grid.spec.style=="ssk_striped_rows",
  "Items must reuse Balance's header and row backgrounds")
assert(not stack.rows.grid.spec.draw_horizontal_lines and stack.rows.grid.spec.draw_vertical_lines,
  "Items must keep column dividers without drifting horizontal lines")
assert(#headers==7 and #cells==14,"Manifest list acquired unrelated stock items or lost columns")
for i=1,7 do assert(headers[i].style.width==cells[i].style.width,"Header and row columns must use identical widths") end
assert(LOC(headers[5].caption)=="Used /s" and LOC(headers[7].caption)=="Empty in")
local favourite=assert(find(ir,function(e)return e.tags.ssk_ui=="bal_fav" and e.tags.key=="item/iron-plate" end))
assert(favourite.spec.style=="tool_button" and favourite.style.width==24)
local was_favourite=us.bal_favs.items["item/iron-plate"]
assert(click(favourite) and us.bal_favs.items["item/iron-plate"]~=was_favourite)
us.bal_favs.items["item/iron-plate"]=true;us.bal_favs.items["item/coal"]=true;UI.refresh(player)
assert(items_root().list.box.viewport.stack.rows.grid.children[1].tags.key=="item/iron-plate","Favourites must sort first")
assert(not us.se_logistics.items_members.coal,"A favourite outside shipping manifests escaped the list scope")
local pick=assert(tagged(items_root(),"items-select",function(t)return t.material=="copper-plate" end))
assert(click(pick) and us.se_logistics.material=="copper-plate")
local usage=assert(tagged(items_root(),"items-usage"));usage.state=false
assert(UI.on_checked{element=usage,player_index=1} and us.se_logistics.items_history.bal_usage_breakdown==false)
local zero=assert(tagged(items_root(),"items-zero"));zero.state=true
assert(UI.on_checked{element=zero,player_index=1} and us.se_logistics.items_history.bal_history_from_zero)
local search=items_root().list.strip.controls.search;search.text="iron"
assert(UI.on_text_changed{element=search,player_index=1})
assert(#items_root().list.box.viewport.stack.rows.grid.children==7 and items_root().list.strip.controls.search==search,"Search must preserve its focused input")
assert(click(tagged(items_root(),"items-clear-search")))
local BalanceRows=TREQ("scripts.balance")
local original_rows=BalanceRows.rows
BalanceRows.rows=function()return {{key="item/iron-plate",cons=2,stock=120,eta=60}},60,{},true end
us.se_logistics.material="iron-plate";UI.refresh(player)
cells=items_root().list.box.viewport.stack.rows.grid.children
assert(cells[5].caption=="2.00" and cells[6].caption=="120" and LOC(cells[7].caption)=="≈ 1 min","Consumption/stock/depletion must use Balance values")
us.se_logistics.quality="normal";UI.refresh(player)
cells=items_root().list.box.viewport.stack.rows.grid.children
assert(cells[5].caption=="—" and cells[6].caption=="—" and cells[7].caption=="—","All-quality measurements leaked into a selected-quality view")
BalanceRows.rows=original_rows;us.se_logistics.quality=nil;UI.refresh(player)
-- Standalone stock renderer remains covered for other callers.
tab(2,"items")
local legacy_items=player.gui.screen.add{type="flow",name="legacy_items_contract",direction="vertical"}
local function refresh_legacy() Panels.items(legacy_items,player,origin,us.period,us.se_logistics,1200,700,Data.query(player.force,origin,game.tick,us.period,{material=us.se_logistics.material,timing="either"})) end
storage.stock={};storage.stock_basis="physical-storage-v2"
refresh_legacy()
assert(legacy_items.se_stock_chart,"Items is missing its stock chart")
assert(us.se_logistics.material=="iron-plate","Subtab navigation discarded material selection")
assert(Panels.stock_value(player,origin,us.se_logistics)==nil,"Missing physical scan became zero stock")
local stock_targets=legacy_items.se_stock_chart.se_panel_targets
assert(#stock_targets.children==0,"Missing scans acquired fabricated stock bars")
-- These are isolated measured stock fixtures, never shipping-ledger records.
storage.stock={}
for i,count in ipairs({50,80,30}) do storage.stock[i]={tick=game.tick-(3-i)*600,s={[origin.index]={["item/iron-plate"]=count}}} end
local StockHistory=TREQ("scripts.history")
local old_build=StockHistory.build
StockHistory.build=function(sidx,period,key)
  return {stock={{tick=game.tick-1200,count=50,measured=true},
    {tick=game.tick-600,count=80,measured=true},{tick=game.tick,count=30,measured=true}}}
end
refresh_legacy()
assert(Panels.stock_value(player,origin,us.se_logistics)==30)
stock_targets=legacy_items.se_stock_chart.se_panel_targets
assert(#stock_targets.children==3)
for i,target in ipairs(stock_targets.children) do
  assert(target.tags.se_stock_sample and target.tags.measured,"Completed stock scan lost measured identity")
  assert(target.style.width<=6,"Unjoined scan became a wide assumed stock interval")
  if i>1 then
    local previous=stock_targets.children[i-1]
    assert(previous.style.left_margin+previous.style.width<target.style.left_margin,"Unknown stock history was filled")
  end
end
-- Isolated renderer contract: the history provider, not this panel, decides
-- which rate estimates join physical scans and where unknown history remains.
StockHistory.build=function(sidx,period,key)
  assert(sidx==origin.index and key=="item/iron-plate")
  return {stock_transport_incomplete=true,stock={{tick=game.tick-1200,count=50,measured=true},
    {tick=game.tick-900,count=60,joined=true},
    {tick=game.tick-600,count=80,measured=true,joined=true},
    {tick=game.tick-300,count=65,joined=true,live=true},
    {tick=game.tick,count=30,measured=true}}}
end
refresh_legacy()
StockHistory.build=old_build
stock_targets=legacy_items.se_stock_chart.se_panel_targets
assert(#stock_targets.children==5)
for i=2,4 do
  local previous,current=stock_targets.children[i-1],stock_targets.children[i]
  assert(previous.style.left_margin+previous.style.width==current.style.left_margin,"Covered stock estimates must share midpoint edges")
end
for _,target in ipairs(stock_targets.children) do if target.tags.measured then
  assert(target.style.width<=6,"Joined physical scan inherited an estimate interval's width")
end end
assert(stock_targets.children[4].tags.live and not stock_targets.children[4].tags.measured)
assert(LOC(stock_targets.children[4].tooltip):find("Estimated stock since last scan",1,true))
assert(LOC(stock_targets.children[4].tooltip):find("items\n\nObserved quantities only; coverage is incomplete",1,true)
  and not LOC(stock_targets.children[1].tooltip):find("coverage is incomplete",1,true),
  "Incomplete accounting must qualify estimates while retaining physical measurement identity")
local stock_legend=find(legacy_items,function(e)
  return e.type=="label" and e.tooltip and LOC(e.tooltip):find("Estimates start from the last physical scan",1,true)
end)
assert(stock_legend and LOC(stock_legend.tooltip):find("coverage is incomplete",1,true))
assert(stock_targets.children[4].style.left_margin+stock_targets.children[4].style.width<stock_targets.children[5].style.left_margin,"A missing rate interval acquired an estimate")
local stock_chart=legacy_items.se_stock_chart
local measured_bars,estimated_bars,outlines=#shapes(stock_chart,"measured"),#shapes(stock_chart,"estimated"),#shapes(stock_chart,"outline")
assert(measured_bars==3 and estimated_bars==2 and outlines==20,"Stock measured/estimated bars need distinct fills and four outlines each")
assert(click(tagged(legacy_items,"history",function(t) return t.direction=="exports" end)))
assert(us.se_logistics.view=="history" and us.se_logistics.history.return_view=="items" and us.se_logistics.history.material=="iron-plate")
assert(#Panels.last_records(us.se_logistics.history)==1 and Panels.last_records(us.se_logistics.history)[1].sent[1].count==1000)
assert(click(tagged(panel().se_tabs.se_history,"panel-return")))
assert(us.se_logistics.view=="items" and us.se_logistics.material=="iron-plate")
us.se_logistics.quality="normal";refresh_legacy()
assert(Panels.stock_value(player,origin,us.se_logistics)==nil,"All-quality stock misrepresented as a single quality")
assert(#legacy_items.se_stock_chart.se_panel_targets.children==0)
us.se_logistics.quality=nil
legacy_items.destroy()
-- The Cannon method shows witnessed effects with unknown manifests, no route.
us.se_logistics.material=nil;us.se_logistics.quality=nil;us.se_logistics.method=nil;us.se_logistics.history={method="cannon"}
tab(3,"history")
assert(#Panels.last_records(us.se_logistics.history)==3,"Ordinary History must show all transport methods and materials")
us.se_logistics.history.route,us.se_logistics.history.direction="stale-route","exports"
UI.refresh(player,true)
assert(#Panels.last_records(us.se_logistics.history)==3,"Ordinary History must ignore saved route and direction without a drilldown")
assert(not panel().se_tabs.se_history.toolbar)
tab(1,"flow")
assert(click(tagged(panel().se_tabs.se_history.parent.se_flow.viewport.body,"history",function(t)return t.unpaired end)))
assert(#Panels.last_records(us.se_logistics.history)==1)
record=Panels.last_records(us.se_logistics.history)[1]
assert(record.method=="cannon" and record.sent==nil and record.received==nil and record.receiver==nil)
receiver=assert(tagged(panel().se_tabs.se_history,"panel-jump",function(t) return t.side=="receiver" end))
assert(not receiver.enabled,"Unknown cannon destination exposed an enabled receiver jump")
-- Surface changes and unsupported-provider removal preserve ordinary UI behavior.
us.se_logistics.method=nil;us.se_logistics.history={};tab(1,"flow")
local found=false
for i,v in pairs(us.surface_names) do if v==orbit.name then
  window=player.gui.screen.ssk_main;window.ssk_window_bar.ssk_surface_picker.selected_index=i
  assert(UI.on_selection{element=window.ssk_window_bar.ssk_surface_picker,player_index=1});found=true
end end
assert(found and us.sidx==orbit.index,"Transport-only surface absent from scope picker")
UI.close(player);UI.open(player)
assert(us.tab_id=="transfers" and us.surface==orbit.name)
-- Two empty scopes must refresh the centre label even with identical totals.
local render_fixture=player.gui.screen.add{type="flow",name="se_renderer_fixture",direction="vertical"}
local scope_state={view="flow"}
local empty_a={valid=true,index=502,name="SE Empty A",find_entities_filtered=function() return {} end}
local empty_b={valid=true,index=503,name="SE Empty B",find_entities_filtered=function() return {} end}
for _,scope in ipairs({empty_a,empty_b}) do
  SEView.render(render_fixture,player,scope,600,scope_state,900,600)
  local body=render_fixture.ssk_se_logistics.se_tabs.se_flow.viewport.body
  local center=body.se_graph.se_center_wrap.se_center
  assert(LOC(center.children[1].caption)==scope.name,"Empty Flow scope retained another surface label")
  assert(#center.children==1,"A surface without SE zone data shows only its name: no stock count or subtitles")
end
-- An SE zone lists SE's own Universe Explorer details in the centre card, and
-- its top resources take the place of the stored-items count.
do
  local saved_remote=remote
  local controls={["iron-ore"]={frequency=1,size=1.5,richness=2},["copper-ore"]={frequency=1,size=1,richness=1},
    coal={frequency=0.5,size=1,richness=1},stone={frequency=2,size=2,richness=2},["uranium-ore"]={frequency=0.25,size=1,richness=1},
    ["crude-oil"]={frequency=1,size=0.5,richness=0.5},["se-cryonite"]={frequency=0,size=1,richness=1},
    ["enemy-base"]={frequency=6,size=6,richness=6},trees={frequency=6,size=6,richness=6}}
  local zone_surface={valid=true,index=504,name="SE Zone",find_entities_filtered=function() return {} end,
    map_gen_settings={autoplace_controls=controls}}
  local zones={[3]={index=3,type="star",name="Calidus",parent_index=7},[7]={index=7,type="planet",name="Arid Star",parent_index=3},
    [9]={index=9,type="moon",name="SE Zone",parent_index=7,primary_resource="iron-ore",radius=4210,ticks_per_day=36000,
      tags={"water_none","moisture_low","enemy_high","temperature_hot"}}}
  local fns={get_zone_from_surface_index=function() return zones[9] end,
    get_zone_from_zone_index=function(a) return zones[a.zone_index] end,
    get_zone_icon=function(a) return a.zone_index==9 and "virtual-signal/se-moon" or a.zone_index==3 and "virtual-signal/se-star" or "virtual-signal/se-planet" end,
    threat_for_surface=function() return 0.35 end,robot_attrition_for_surface=function() return 1.5 end,
    solar_for_surface=function() return 0.8 end,hazards_for_surface=function() return {"waterless"} end}
  local api={};for k in pairs(fns) do api[k]=true end
  remote={interfaces={["space-exploration"]=api},call=function(_,fn,args) return fns[fn](args) end}
  local saved_entity,saved_control=prototypes.entity,prototypes.autoplace_control
  local ores={}
  for name in pairs(controls) do
    if name~="enemy-base" and name~="trees" then ores[name]={name=name,localised_name={"entity-name."..name}} end
  end
  prototypes.entity=setmetatable(ores,{__index=saved_entity})
  local catalog={}
  for name in pairs(controls) do
    catalog[name]={name=name,category=name=="enemy-base" and "enemy" or name=="trees" and "terrain" or "resource",
      localised_name={"autoplace-control-names."..name}}
  end
  prototypes.autoplace_control=catalog
  SEView.render(render_fixture,player,zone_surface,600,{view="flow"},1600,700)
  local body=render_fixture.ssk_se_logistics.se_tabs.se_flow.viewport.body
  local center=body.se_graph.se_center_wrap.se_center
  local zone=assert(center.se_zone,"SE zone properties missing from the centre card")
  local names={}
  for i,child in ipairs(zone.children) do names[i]=child.name:gsub("^se_","") end
  assert(table.concat(names,",")=="type,parent_planet,parent_star,resource,environment,threat,attrition,solar,hazards,daynight,radius",
    "Unexpected SE zone rows: "..table.concat(names,","))
  local function caption(name) return zone["se_"..name].se_value.caption end
  assert(caption("type")[3][1]=="space-exploration.moon" and caption("type")[2]=="[img=virtual-signal/se-moon] ")
  -- The chain runs moon -> planet -> star and stops at the star (SE has no
  -- galaxy); a bogus star parent_index must not loop back to the planet.
  assert(caption("parent_planet")[3]=="Arid Star" and caption("parent_planet")[2]=="[img=virtual-signal/se-planet] "
    and zone.se_parent_planet.children[1].caption[2][1]=="space-exploration.planet")
  assert(caption("parent_star")[3]=="Calidus" and caption("parent_star")[2]=="[img=virtual-signal/se-star] "
    and zone.se_parent_star.children[1].caption[2][1]=="space-exploration.star")
  for _,line in ipairs(zone.children) do
    assert(line.children[1].spec.style==nil,"Zone keys must use the readable default label colour, not grey_label")
  end
  assert(caption("resource")[2]=="[img=entity/iron-ore] " and caption("resource")[3][1]=="entity-name.iron-ore")
  local env=caption("environment");local tags={}
  for i=3,#env,2 do tags[#tags+1]=env[i][1] end
  assert(table.concat(tags,",")=="space-exploration.climate_moisture_low,space-exploration.climate_temperature_hot,space-exploration.climate_water_none",
    "Environment tags must reuse SE climate names and skip enemy tags")
  assert(caption("threat")=="35%" and caption("attrition")=="1.50" and caption("solar")=="80%" and caption("radius")=="4210")
  assert(zone.se_attrition.children[1].caption[2][1]=="space-exploration.attrition-type-wind")
  assert(caption("hazards")[2]=="[img=utility/warning_icon] " and caption("hazards")[3][1]=="space-exploration.zone-hazard-waterless"
    and zone.se_hazards.se_value.tooltip[3][1]=="space-exploration.zone-hazard-tooltip-waterless")
  assert(caption("daynight")[1]=="time-symbol-minutes" and caption("daynight")[2]=="10.00")
  -- Top five resources at the bottom of the card, ranked like SE (frequency ×
  -- size × richness), showing size and richness; no stored-items count.
  local grid=assert(center.se_resources,"Top resources missing from the centre card")
  assert(center.children[#center.children]==grid,"Resources must be the last part of the card")
  for _,e in ipairs(center.children) do
    assert(e.name~="se_stock" and e.name~="se_stock_row","Stored items count must be gone")
  end
  assert(grid.column_count==3 and #grid.children==18,"Resources must be a header plus five rows")
  assert(grid.children[1].caption[1]=="space-exploration.zonelist-resources-header"
    and grid.children[2].caption[1]=="gui-map-generator.size" and grid.children[3].caption[1]=="gui-map-generator.richness")
  local ranked={}
  for i=1,5 do
    local name=grid["se_resource_"..i]
    ranked[i]=name.caption[3][1]:gsub("^entity%-name%.","")
    assert(name.caption[2]=="[img=entity/"..ranked[i].."] " and name.tooltip[1]=="space-exploration.zonelist-resource-bar-tooltip")
  end
  assert(table.concat(ranked,",")=="stone,iron-ore,copper-ore,coal,crude-oil",
    "Resources must rank by SE's estimate, skip non-resources and empty controls: "..table.concat(ranked,","))
  assert(grid.children[5].caption=="200%" and grid.children[6].caption=="200%","Stone size and richness")
  assert(grid.children[8].caption=="150%" and grid.children[9].caption=="200%","Iron size and richness")
  local inner=center.style.width-24
  assert(grid.children[4].style.width+grid.children[5].style.width+grid.children[6].style.width+12<=inner,"Resource columns overflow the card")
  assert(not body.se_zone_panel,"Zone info must stay in the centre card")
  -- Same scope and shipments, but SE's runtime values changed (robot attrition
  -- is a map setting; resources can be edited): a refresh shows the new values.
  fns.robot_attrition_for_surface=function() return 3 end
  controls.stone.richness=3
  SEView.render(render_fixture,player,zone_surface,600,{view="flow"},1600,700)
  center=render_fixture.ssk_se_logistics.se_tabs.se_flow.viewport.body.se_graph.se_center_wrap.se_center
  assert(center.se_zone.se_attrition.se_value.caption=="3.00","Zone card kept a stale robot interference value")
  assert(center.se_resources.children[6].caption=="300%","Zone card kept a stale resource richness")
  fns.robot_attrition_for_surface=function() return 1.5 end
  controls.stone.richness=2
  -- Like SE's Universe Explorer, an orbit lists no resources.
  zones[9].type="orbit"
  SEView.render(render_fixture,player,zone_surface,600,{view="flow",scope_revision=2},1600,700)
  local orbit_card=render_fixture.ssk_se_logistics.se_tabs.se_flow.viewport.body.se_graph.se_center_wrap.se_center
  assert(orbit_card.se_zone and not orbit_card.se_resources,"Orbit must not list mapgen resources")
  local orbit_rows={}
  for i,child in ipairs(orbit_card.se_zone.children) do orbit_rows[i]=child.name:gsub("^se_","") end
  assert(table.concat(orbit_rows,","):find("^type,parent_planet,parent_star,"),
    "An orbit shows the chain from the body it circles up to the star: "..table.concat(orbit_rows,","))
  zones[9].type="moon"
  assert(LOC(body.se_flow_note.tooltip):find("Ribbon width",1,true),"Ribbon notes must stay on the Flow help tooltip")
  -- Without SE's remote interface the card shows only the surface name.
  remote={interfaces={},call=function() error("no SE") end}
  SEView.render(render_fixture,player,zone_surface,600,{view="flow",scope_revision=1},1600,700)
  center=render_fixture.ssk_se_logistics.se_tabs.se_flow.viewport.body.se_graph.se_center_wrap.se_center
  assert(#center.children==1 and not center.se_zone and not center.se_resources,"Missing SE data must leave only the name")
  prototypes.entity,prototypes.autoplace_control=saved_entity,saved_control
  remote=saved_remote
end
-- A newly observed off-page route must update native pagination even when the
-- currently visible manifests did not change.
local old_query=Data.query
local page_data={materials={"iron-plate"},qualities={"normal"},coverage={},groups={imports={},exports={}}}
local function add_route(i)
  page_data.groups.exports[i]={id="renderer-route-"..i,remote={surface=empty_b},methods={
    {method="rocket",sent={{name="iron-plate",quality="normal",count=100}}}}}
end
for i=1,3 do add_route(i) end
Data.query=function() return page_data end
local paging_state={view="flow",material="iron-plate"}
SEView.render(render_fixture,player,empty_a,600,paging_state,900,600)
local function next_exports() return tagged(render_fixture,"page",function(t) return t.side=="exports" and t.delta==1 end) end
assert(paging_state.exports_pages==1 and next_exports().enabled==false)
-- Compact route cards fit four one-method routes in this 600 px fixture.
add_route(4);add_route(5)
SEView.render(render_fixture,player,empty_a,600,paging_state,900,600)
assert(paging_state.exports_pages==2 and next_exports().enabled==true,"Off-page route did not refresh pagination")
-- Items grouping: each side's eight most transported items (each quality
-- separately, over that side's routes) get a row; an item keeps one colour on
-- both sides and in every card; everything else merges into a grey Other row.
do
  local function c(name,count,quality) return {name=name,quality=quality or "normal",count=count} end
  local cargo={c("iron-plate",100),c("copper-plate",60),c("steel-plate",40),c("iron-plate",30,"rare"),c("stone",20),
    c("coal",10),c("plastic-bar",9),c("sulfur",8),c("battery",7),c("wood",1)}
  local mixed={id="mixed-route",remote={surface=empty_b},sent=cargo,sent_observed=cargo,received=nil,received_observed={},
    methods={{method="rocket",sent={cargo[1],cargo[2]}},{method="cannon",sent=nil,sent_observed={table.unpack(cargo,3)}}}}
  local inbound={c("iron-plate",50),c("wood",3)}
  local back={id="inbound-route",remote={surface=empty_b},sent=inbound,sent_observed=inbound,received=inbound,received_observed=inbound,
    methods={{method="rocket",sent=inbound,received=inbound}}}
  local saved_exports,saved_imports=page_data.groups.exports,page_data.groups.imports
  page_data.groups.exports,page_data.groups.imports={mixed},{back}
  local items_state={view="flow",group="items"}
  SEView.render(render_fixture,player,empty_a,600,items_state,900,600)
  local export_card=assert(find(render_fixture,function(e) return e.name=="se_route_card" and e.rows.item_8 end))
  local rows=export_card.rows
  assert(rows.item_1.children[1].sprite=="item/iron-plate" and rows.item_1.children[4].caption=="100"
    and rows.item_2.children[1].sprite=="item/copper-plate" and rows.item_4.children[1].sprite=="item/iron-plate"
    and rows.item_8.children[1].sprite=="item/sulfur" and not rows.item_9 and rows.item_other and #rows.children==10,
    "Items rows must follow the surface's top eight, largest first")
  assert(LOC(rows.item_other.children[1].caption)=="Other items (2)"
    and rows.item_other.children[3].caption=="8" and rows.item_other.children[4].caption=="—",
    "The Other row counts the remaining items and keeps unknown receipts unknown")
  assert(tagged(render_fixture,"history",function(t) return t.material=="iron-plate" and t.quality=="rare" end),
    "Each quality must keep its own item row")
  -- Imports rank on their own: wood is outside the exports' top eight but in the imports'.
  local import_card=assert(find(render_fixture,function(e) return e.name=="se_route_card" and e.rows.item_2 and not e.rows.item_3 end))
  assert(import_card.rows.item_1.children[1].sprite=="item/iron-plate" and import_card.rows.item_2.children[1].sprite=="item/wood"
    and not import_card.rows.item_other,"Each side must rank its own top eight")
  -- Stripes: iron keeps one colour on both sides, colours stay unique per side, grey once.
  -- Card stripes only: the GUI plot below the cards draws with the same sprites.
  local stripes={}
  local function visit(e)
    if e.name=="se_gui_plot" then return end
    local s=e.spec and e.spec.sprite or e.sprite
    if type(s)=="string" and s:find("^ssk%-plot%-ribbon_") then stripes[s]=(stripes[s] or 0)+1 end
    for _,child in ipairs(e.children or {}) do visit(child) end
  end
  visit(render_fixture)
  local plotted=0
  find(render_fixture,function(e)
    if e.name=="se_gui_plot" then
      find(e,function(x) local s=x.spec and x.spec.sprite or x.sprite
        if s=="ssk-plot-ribbon_item_1" then plotted=plotted+1 end end)
    end
  end)
  assert(plotted>0,"The GUI plot must draw the item colour")
  assert(stripes["ssk-plot-ribbon_item_1"]==2 and stripes["ssk-plot-ribbon_item_other"]==1,"Iron must share its colour across sides")
  local total=0;for slot=1,8 do total=total+(stripes["ssk-plot-ribbon_item_"..slot] or 0) end
  assert(total==10,"Eight export rows and two import rows need item colours")
  for slot=2,8 do assert((stripes["ssk-plot-ribbon_item_"..slot] or 0)>=1,"Each export top item needs its own colour") end
  for key in pairs(stripes) do assert(not key:find("ribbon_in_") and not key:find("ribbon_out_"),"Items mode must not use direction shades") end
  page_data.groups.exports,page_data.groups.imports=saved_exports,saved_imports
end
-- Exact payloads do not make a shortened or truncated recording window complete.
local coverage_seconds,coverage_truncated,coverage_records=1,false,{}
Data.query=function() return {materials={"iron-plate"},qualities={"normal"},coverage={rocket=coverage_seconds},
  groups={imports={},exports={}},records=coverage_records,seconds=600,
  from_tick=game.tick-36000,to_tick=game.tick,truncated=coverage_truncated} end
local coverage_state={view="items",method="rocket",material="iron-plate"}
local function export_summary()
  local data=Data.query()
  data.receipt_coverage=false
  data.sent_coverage=not coverage_truncated and coverage_seconds>=600
  Panels.items(render_fixture,player,empty_a,600,coverage_state,1200,700,data)
  return render_fixture.se_item_summary.children[2]
end
assert(export_summary().children[2].caption=="—","Partial recording became a known zero export")
coverage_seconds,coverage_truncated=600,true
assert(export_summary().children[2].caption=="—","Truncated recording became a known zero export")
coverage_records={{key="coverage:sent",method="rocket",direction="exports",tick=game.tick-60,
  sent={{name="iron-plate",quality="normal",count=100}}}}
local partial_summary=export_summary()
assert(partial_summary.children[2].caption=="100" and LOC(partial_summary.children[3].caption):find("known",1,true),
  "Observed totals from a truncated ledger must retain their partial qualifier")
coverage_records,coverage_truncated={},false
assert(export_summary().children[2].caption=="0","Complete empty rocket recording lost its observed zero")
Data.query=old_query
render_fixture.destroy()
-- Explicit isolated renderer contract: genuine provider fixtures above never
-- acquire receipt data. Only this local display input has a known receipt.
local truth_fixture=player.gui.screen.add{type="flow",name="se_truth_renderer_fixture",direction="vertical"}
local item=function(count) return {{name="iron-plate",count=count,quality="normal"}} end
local renderer_state={history={material="iron-plate"}}
local history_data={
  fixture_kind="isolated_renderer_contract",from_tick=game.tick-600,to_tick=game.tick,
  records={{key="fixture:received",method="rocket",direction="imports",tick=game.tick-500,
    arrival_tick=game.tick-60,sent=item(900),received=item(700)},
    {key="fixture:sent",method="rocket",direction="exports",tick=game.tick-120,sent=item(1000),
      received=item(990),arrival_tick=game.tick-30}}}
Panels.history(truth_fixture,player,origin,10,renderer_state,900,500,history_data)
local truth_plot=truth_fixture.se_history_layout.se_history_plot
local positives,negatives=shapes(truth_plot,"incoming"),shapes(truth_plot,"outgoing")
assert(#positives==1 and #negatives==1)
local positive,negative=positives[1],negatives[1]
assert(positive.parent.style.top_margin+positive.style.height<negative.parent.style.top_margin,
  "Known receipt/export bars lost common signed baseline")
assert(Panels.last_records(renderer_state.history)[1].received[1].count==700 and Panels.last_records(renderer_state.history)[2].sent[1].count==1000)
local shipment_log=truth_fixture.se_history_layout.se_history_log
assert(LOC(shipment_log.se_shipment_1.children[1].children[2].tooltip)==LOC({"production-flow.se-ui-arrival-time"})
  and LOC(shipment_log.se_shipment_2.children[1].children[2].tooltip)==LOC({"production-flow.se-ui-departure-time"}),
  "History time tooltip must describe the displayed local boundary, including received exports")
local received_fixture=history_data.records[1]
received_fixture.sent={}
received_fixture.received[2]={name="iron-plate",quality="rare",count=25}
renderer_state.history.expanded=received_fixture.key
Panels.history(truth_fixture,player,origin,10,renderer_state,600,500,history_data)
local tables=shipment_log.se_shipment_1.manifest_detail.manifests
assert(not tables.sent,"Receipt detail must not keep a separate Sent table")
local received=tables.received.manifest
assert(received.column_count==2 and #received.children==4 and received.children[3].received.caption=="700"
  and received.children[4].received.caption=="25" and received.children[4].lost.caption=="0"
  and LOC(received.children[4].children[1].caption):find("rare",1,true),
  "Manifest merged or discarded item qualities")
assert((received.children[3].style.width+6)*3<=tables.received.style.width,
  "Compact manifest columns must fit within the card")
received_fixture.sent=item(900)
received_fixture.received[2]=nil
-- A measured receipt against a known manifest is one table: item, lost, received.
local saved_received=received_fixture.received
received_fixture.sent={{name="iron-plate",quality="normal",count=900},{name="copper-plate",quality="normal",count=50}}
received_fixture.received={{name="iron-plate",quality="normal",count=700},{name="steel-plate",quality="normal",count=5}}
Panels.history(truth_fixture,player,origin,10,renderer_state,900,500,history_data)
local receipt=shipment_log.se_shipment_1.manifest_detail.manifests
local grid=receipt.received.manifest
assert(not receipt.sent and grid.column_count==3 and receipt.received.children[1]==grid,
  "A measured receipt must be one table without subtitles, one column per item up to four")
local all=grid.children
assert(#all==6,"Receipt table must have one header row and cover each item once")
for i=1,3 do
  local h=all[i]
  assert(h.name=="header_"..i and LOC(h.item.caption)=="Item" and LOC(h.lost.caption)=="Lost" and LOC(h.received.caption)=="Received"
    and h.lost.style.horizontal_align=="right" and h.item.style.width==all[3+i].children[1].style.width,
    "Receipt header must name and align with item, lost, received")
end
local rc={all[4],all[5],all[6]}
assert(LOC(rc[1].children[1].caption):find("[item=iron-plate]",1,true) and rc[1].lost.caption=="−200"
  and rc[1].lost.spec.style=="red_label" and rc[1].received.caption=="700" and rc[1].tags.sent==900,
  "Receipt cell must read item, negative loss, received")
assert(rc[2].lost.caption=="−50" and rc[2].received.caption=="0","A wholly lost item must show its full loss")
assert(rc[3].lost.caption=="0" and rc[3].lost.spec.style=="grey_label" and rc[3].received.caption=="5" and rc[3].tags.sent==nil,
  "An item missing from the sent manifest must not invent a loss")
assert(rc[1].children[1].style.width+rc[1].lost.style.width+rc[1].received.style.width+12<=rc[1].style.width,
  "Receipt cell columns must fit their cell")
local whole=TREQ("scripts.transfer_manifest_ui").receipt_rows(item(100),item(100))
assert(#whole==1 and whole[1].lost==0 and whole[1].received==100,"A whole cannon receipt must report zero loss")
received_fixture.received=saved_received
received_fixture.sent=item(900)
-- A cannon shot that no delivery chest caught warns on its main row, not in the detail.
local catcher_data={}
for k,v in pairs(history_data) do catcher_data[k]=v end
catcher_data.records={
  {key="fixture:spill",method="cannon",direction="exports",status="spilled",tick=game.tick-300,landed_tick=game.tick-200,sent=item(100)},
  {key="fixture:no-chest",method="cannon",direction="exports",status="arrived",tick=game.tick-250,landed_tick=game.tick-150,sent=item(100)},
  {key="fixture:caught",method="cannon",direction="exports",status="received",tick=game.tick-220,arrival_tick=game.tick-100,sent=item(100),received=item(100)}}
local catcher_state={history={material="iron-plate"}}
Panels.history(truth_fixture,player,origin,10,catcher_state,900,500,catcher_data)
local catcher_log=truth_fixture.se_history_layout.se_history_log
local warned=0
for i=1,3 do
  local main=catcher_log["se_shipment_"..i].children[1]
  local record=Panels.last_records(catcher_state.history)[i]
  local warning=main.no_catcher
  if record.received==nil then
    warned=warned+1
    assert(warning and warning.children[1].sprite=="utility/warning_icon"
      and LOC(warning.tooltip):find("No delivery chest caught this shot.",1,true),"Uncaught cannon shot lost its main-row warning")
  else
    assert(not warning,"A caught cannon shot must not warn")
  end
end
assert(warned==2,"Both uncaught shots must warn")
-- An independently identified exchange can contain both local directions.
history_data.records[1].exchange_id=42;history_data.records[1].from={id=1};history_data.records[1].to={id=2}
history_data.records[2].exchange_id=42;history_data.records[2].from={id=2};history_data.records[2].to={id=1}
renderer_state.history.axis="events"
Panels.history(truth_fixture,player,origin,10,renderer_state,900,500,history_data)
assert(#Panels.last_exchanges(renderer_state.history)==1 and Panels.last_exchanges(renderer_state.history)[1].received==700
  and Panels.last_exchanges(renderer_state.history)[1].sent==1000,"Exchange netted or split opposite directions")
local chosen=assert(tagged(truth_fixture,"panel-exchange"))
assert(Panels.on_click({element=chosen},renderer_state))
Panels.history(truth_fixture,player,origin,10,renderer_state,900,500,history_data)
assert(renderer_state.history.exchange and #Panels.last_records(renderer_state.history)==2,"Exchange filtering discarded a direction")
renderer_state.history.exchange=nil
renderer_state.history.axis="time"
local measured_records=history_data.records
history_data.records={{key="dispatch",method="rocket",direction="imports",tick=game.tick-120,sent=item(750)}}
Panels.history(truth_fixture,player,origin,10,renderer_state,900,500,history_data)
local inbound=assert(tagged(truth_fixture,"panel-bucket"))
assert(LOC(inbound.tooltip):find("Dispatched here: 750 items",1,true),"Time mode lost the inbound dispatch quantity")
renderer_state.history.axis="events"
Panels.history(truth_fixture,player,origin,10,renderer_state,900,500,history_data)
local inbound_group=Panels.last_exchanges(renderer_state.history)[1]
assert(inbound_group.inbound_dispatch==750 and not inbound_group.received_known and not inbound_group.unmeasured)
assert(LOC(tagged(truth_fixture,"panel-exchange").tooltip):find("receipt unknown",1,true))
assert(#shapes(truth_plot,"inbound_dispatch")==1 and #shapes(truth_plot,"incoming")==0,
  "Inbound dispatch must have a distinct filled bar")
local note=truth_fixture.se_history_layout.se_history_note
assert(LOC(note.caption):find("Received amounts are measured at landing pads",1,true))
local iron_prototype=rawget(prototypes.item,"iron-plate")
prototypes.item["iron-plate"]={stack_size=100}
history_data.records[1].cargo_loss,history_data.records[1].pad_miss=.2,1
for _,axis in ipairs({"events","time"}) do
  renderer_state.history.axis=axis
  Panels.history(truth_fixture,player,origin,10,renderer_state,900,500,history_data)
  local target=tagged(truth_fixture,axis=="events" and "panel-exchange" or "panel-bucket")
  assert(LOC(target.tooltip):find("of 750 sent (80.1% retained)",1,true))
  assert(#shapes(truth_plot,"inbound_estimate")==1 and #shapes(truth_plot,"inbound_dispatch")==0)
end
prototypes.item["iron-plate"]=iron_prototype
history_data.records=measured_records
local anchor={tick=game.tick-120,count=1234,measured=true}
StockHistory.build=function() return {stock={anchor}} end
Panels.items(truth_fixture,player,origin,10,{material="iron-plate"},900,500,history_data)
StockHistory.build=old_build
local markers=0
for _,e in ipairs(truth_fixture.se_stock_chart.se_panel_targets.children) do
  if e.tags.se_import_receipt then markers=markers+1;assert(e.tags.count==700 and e.tags.tick==game.tick-60) end
end
assert(markers==1 and anchor.count==1234,"Import marker was invented, duplicated or changed the stock measurement")
history_data.records={}
for i=1,120 do history_data.records[i]={key="dense-exchange:"..i,direction="exports",method="rocket",
  tick=game.tick-600+i*4,sent=item(1)} end
renderer_state.history={material="iron-plate",axis="events"}
Panels.history(truth_fixture,player,origin,10,renderer_state,900,500,history_data)
assert(#Panels.last_exchanges(renderer_state.history)==120 and renderer_state.history._event_pages==4,"Compact pages dropped old exchanges")
local latest_hits=truth_fixture.se_history_layout.se_history_plot.se_history_chart.se_panel_targets.children
assert(#latest_hits==18 and latest_hits[#latest_hits].style.left_margin+latest_hits[#latest_hits].style.width==883,
  "Short latest page must end at the right of the plot")
local back=assert(tagged(truth_fixture,"panel-exchange-page",function(t)return t.delta==-1 end))
assert(back.enabled and Panels.on_click({element=back},renderer_state))
Panels.history(truth_fixture,player,origin,10,renderer_state,900,500,history_data)
assert(renderer_state.history.event_page==3)
local hits=truth_fixture.se_history_layout.se_history_plot.se_history_chart.se_panel_targets.children
assert(#hits==34,"Compact page did not fit the expected exchange count")
for i=2,#hits do assert(hits[i].style.left_margin-hits[i-1].style.left_margin==24,"Exchange gap grew unexpectedly") end
truth_fixture.destroy()
-- Small windows are opt-in. Extremely small windows skip drawing either way.
local normal_resolution,normal_scale,print_message=player.display_resolution,player.display_scale,player.print
local warnings={}
player.print=function(message) warnings[#warnings+1]=message end
for _,case in ipairs({{1280,720,1.5,"items"},{1280,720,2,"items"},{1024,768,2,"items"},{1280,720,2.5,"history"},{919,559,1,"history"}}) do
  player.display_resolution={width=case[1],height=case[2]};player.display_scale=case[3]
  us.se_logistics.view=case[4]
  local before=#warnings
  UI.open(player)
  assert(not UI.is_open(player) and #warnings==before+1)
  UI.refresh(player)
  assert(not UI.is_open(player) and #warnings==before+1)
end
player.mod_settings["ssk-allow-small-window"]={value=true}
local before=#warnings
UI.open(player)
assert(UI.is_open(player) and #warnings==before)
player.display_resolution,player.display_scale={width=1280,height=720},2.5
UI.on_display_changed(player)
local compact_viewport=panel().se_tabs.se_history.viewport
assert(compact_viewport.spec.horizontal_scroll_policy=="auto" and compact_viewport.spec.vertical_scroll_policy=="auto")
player.display_resolution,player.display_scale={width=435,height=287},1
UI.on_display_changed(player)
assert(not UI.is_open(player) and #warnings==before+1)
player.mod_settings["ssk-allow-small-window"]={value=false}
player.display_resolution,player.display_scale={width=920,height=559},1
UI.open(player)
assert(UI.is_open(player) and us.se_logistics.view=="history")
player.display_resolution,player.display_scale={width=1280,height=720},2
UI.on_display_changed(player)
assert(not UI.is_open(player) and #warnings==before+2)
player.mod_settings["ssk-allow-small-window"]=nil
player.display_resolution,player.display_scale,player.print=normal_resolution,normal_scale,print_message
script.active_mods={base="2.1.24"};UI.open(player)
assert(us.tab_id=="balance","Unsupported provider did not fall back")
script.active_mods,defines.events,defines.controllers=saved.mods,saved.events,saved.controllers
us.bal_favs=saved.favs
storage.se_rockets,storage.se_cannons,storage.stock,storage.stock_basis=saved.rockets,saved.cannons,saved.stock,saved.basis
player.valid,player.controller_type=saved.player_valid,saved.controller
player.force.valid,player.force.index=saved.force_valid,saved.force_index
player.surface=saved.surface;player.surface.valid=saved.surface_valid;player.surface.find_entities_filtered=saved.surface_find
remote=saved.remote;game.forces.player=saved.game_force
game.surfaces[501]=nil;game.surfaces[orbit.name]=nil
us.tab_id,us.surface,us.period,us.se_logistics=saved.tab,saved.scope,saved.period,saved.state
UI.open(player)
-- Expanded shipments state what the provider established about the landing.
local function outcome(record) return LOC(Panels.outcome(record)) end
local function shipment(t)
  local r={method="rocket",direction="exports",tick=600,sent={{name="iron-plate",count=1750}}}
  for k,v in pairs(t) do r[k]=v end
  return r
end
assert(outcome(shipment{received={{name="iron-plate",count=1715}},arrival_tick=1200,status="received"})
  =="Measured at 00:00:20: 1715 of 1750 arrived, 35 lost in flight.","Rocket loss not stated")
assert(outcome(shipment{received={{name="iron-plate",count=1750}},arrival_tick=1200,status="received"})
  =="Measured at 00:00:20: all 1750 arrived.")
assert(outcome(shipment{status="padless",landed_tick=1200})=="Landed off a landing pad. Received unknown.")
assert(outcome(shipment{status="unconfirmed",landed_tick=1200})
  =="Landed at 00:00:20 without a landing pad confirmation. Received unknown.")
assert(outcome(shipment{status="unconfirmed"})=="In flight. Received is measured on landing.")
assert(outcome(shipment{method="cannon",status="spilled",landed_tick=720})=="Landed at 00:00:12 and spilled. Received unknown.")
assert(outcome(shipment{method="cannon",status="arrived",landed_tick=720}):find("no delivery chest",1,true))
assert(outcome(shipment{method="cannon",status="lost",landed_tick=720}):find("no longer exists",1,true))
assert(Panels.outcome(shipment{method="cannon",direction="unpaired"})==nil and Panels.outcome(shipment{method="cargo-pod"})==nil,
  "Outcome invented for unpaired or Space Age records")
print("SE TRANSFERS UI PASS: all-cargo Flow/History, Items filters, route handoff, unknown receipts, safe jump revalidation, cannon unknowns, landing outcomes and surface scope")
