-- Native screenshots and translation verification; injected only after packing
-- the clean candidate. GUI handlers are invoked, not physical mouse clicks.
-- Primary stock captures use live factory production and completed inventory scans.
local Native=require("scripts.test_locale_native")
local D=require("scripts.se_transfer_data")
local Endpoints=require("scripts.transfer_endpoints")
local History=require("scripts.history")
local Dense=require("scripts.se_dense_presentation_fixture")
local Exchanges=require("scripts.transfer_exchanges")
local C={}
local step,pending,primed,done=0,nil,false,false
local names={"se-transfers-flow-default","se-transfers-flow-iron","se-transfers-history-iron",
  "se-transfers-history-cannon","se-transfers-items-recent-real","se-transfers-items-factory-history",
  "se-transfers-history-time-filter","se-transfers-flow-orbit","se-transfers-history-empty",
  "se-transfers-flow-copper","se-transfers-history-all-iron","se-transfers-synthetic-grouped-flow",
  "se-transfers-synthetic-signed-history","se-transfers-synthetic-history-page-two","se-transfers-synthetic-flow-page-two",
  "se-balance-flow-transports","se-balance-filtered-transport-history","se-focus-transports","se-full-sankey-transports","se-working-factory-world",
  "se-transfers-history-events","se-transfers-synthetic-import-markers","se-transfers-history-entities","se-transfers-items-cannon-recipes",
  "se-transfers-history-rocket-loss","se-transfers-history-cannon-spill","se-transfers-history-orbit-cannon-imports",
  "se-transfers-flow-moon","se-transfers-flow-moon-orbit",
  "se-transfers-flow-by-item","se-transfers-synthetic-flow-by-item"}
local evidence={stock_layout={synthetic=false,source="completed shipping scanner snapshots + live factory statistics",
  material="item/iron-plate",quality="all",force="player",scope="nauvis",private_cooldown_ticks=1800},
  receipt_amounts="measured-pad-or-chest",cannon_manifests="paired-beam-projectile",events="handler-invocation",capture_game_speed=4,synthetic_captures={}}
local function synthetic_case() return names[step] and names[step]:find("synthetic",1,true)~=nil end
local function find(e,predicate)
  if predicate(e) then return e end
  for _,child in pairs(e.children) do local hit=find(child,predicate);if hit then return hit end end
end
local function tagged(e,action,predicate)
  return find(e,function(child) return child.tags and child.tags.se_logistics==action
    and (not predicate or predicate(child.tags,child)) end)
end
local function generic_action(root,action,predicate)
  return find(root,function(e) return e.tags and e.tags.ssk_ui==action and (not predicate or predicate(e.tags,e)) end)
end
local function graph_evidence(p,tab)
  local root=p.gui.screen.ssk_main
  local counts={imports=0,exports=0,external_supply_targets=0}
  local function contains(value,text)
    if type(value)=="string" then return value:find(text,1,true)~=nil end
    if type(value)=="table" then for _,part in pairs(value) do if contains(part,text) then return true end end end
    return false
  end
  local function visit(e)
    local tags=e.tags or {}
    assert(not tags.ssk_transport_column,"Dedicated transport columns returned")
    if tags.ssk_ui=="transport_history" and tags.provider=="se" and tags.material=="iron-plate" then
      assert(tags.surface_index==game.surfaces.nauvis.index,"Graph transport escaped selected surface")
      counts[tags.direction]=(counts[tags.direction] or 0)+1
    end
    if tags.ssk_sk=="node" and tags.key=="item/iron-plate" and e.tooltip then
      assert(contains(e.tooltip,"transport-flow-external-supply") and contains(e.tooltip,"se-ui-rocket"),
        "Native material hover lost external supply/method details")
      counts.external_supply_targets=counts.external_supply_targets+1
      counts.external_supply_hover=e.tooltip
    end
    for _,child in pairs(e.children) do visit(child) end
  end
  visit(root)
  assert(counts.imports==0 and counts.exports>0 and counts.external_supply_targets>0,
    "Native "..tab.." must merge supply into the material and connect dedicated exports")
  evidence.graphs=evidence.graphs or {};evidence.graphs[tab]=counts
end
local function suppress_tooltips(element)
  element.tooltip=nil
  for _,child in pairs(element.children) do suppress_tooltips(child) end
end
local function panel(p) return assert(p.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_transfers.ssk_se_logistics) end
local function items_root(p) return panel(p).se_tabs.se_items.viewport.body.transport_items end
local function stock_targets(p)
  return items_root(p).inspector.ssk_history_scroll.ssk_history_body.ssk_history_stock_plot.ssk_history_tooltips
end
local function click(UI,p,e) assert(UI.on_click{player_index=p.index,element=assert(e)}) end
local function view(UI,p,index,name)
  local tabs=panel(p).se_tabs;tabs.selected_tab_index=index
  assert(UI.on_tab_changed{player_index=p.index,element=tabs})
  assert(storage.ui[p.index].se_logistics.view==name)
end
local function material(UI,p,name)
  local us=storage.ui[p.index]
  local state=us.se_logistics
  local container=panel(p).se_tabs["se_"..state.view]
  if state.view=="flow" then
    assert(not container.toolbar,"Surface Flow should have no filter toolbar")
    return
  end
  local pick=container.toolbar.controls.se_material
  local selected
  for i,id in pairs(state.materials or {}) do if id==name then selected=i end end
  assert(selected,"Native material not in SE dropdown: "..name)
  pick.selected_index=selected
  assert(UI.on_selection{player_index=p.index,element=pick})
  assert(state.material==name)
  UI.refresh(p,true)
  assert(panel(p).se_tabs["se_"..state.view].toolbar.controls.se_material==pick,"Native refresh rebuilt toolbar")
end
local function reset(UI,p,name,period)
  local us=storage.ui[p.index]
  us.period=period or 3600
  us.se_logistics.material=nil;us.se_logistics.quality=nil;us.se_logistics.method=nil
  us.se_logistics.history={};us.se_logistics.view=name
  UI.refresh(p)
end
-- Flip the Flow grouping switch through its handler, as a click would.
local function group_by(UI,p,state,grouping)
  local switch=assert(find(panel(p).se_tabs.se_flow.viewport.body,function(e) return e.name=="se_group" end),"Flow has no grouping switch")
  switch.switch_state=grouping=="items" and "right" or "left"
  assert(UI.on_switch{player_index=p.index,element=switch})
  assert((state.group or "transport")==grouping)
end
local function item_rows(p)
  local rows,cards=0,0
  local function visit(e)
    if e.name=="se_route_card" then
      cards=cards+1
      assert(not e.rows.method_1 and (e.rows.item_1 or e.rows.item_other),"Items grouping left a method row")
      for _,child in pairs(e.rows.children) do if child.name and child.name:find("^item_") then rows=rows+1 end end
    end
    for _,child in pairs(e.children) do visit(child) end
  end
  visit(panel(p).se_tabs.se_flow.viewport.body)
  assert(cards>0 and rows>=cards,"Items grouping produced no item rows")
  return {cards=cards,rows=rows}
end
-- Received is set only by a measured pad/chest receipt; everything else stays unknown.
local function assert_receipts_measured(records)
  for _,record in ipairs(records) do
    if record.received then assert(record.status=="received" and record.arrival_tick,"Receipt without a measured landing")
    else assert(record.status~="received","Received status without a measured manifest") end
  end
end
local function received_label(record) return record.received and #record.received or "unknown" end
function C.register(UI,config)
  -- The real save covers night-vision detection. Force the same backend here
  -- to cover populated, physically observed rocket/cannon routes as well.
  local GuiPlot=require("scripts.gui_plot")
  local original_needed=GuiPlot.needed
  GuiPlot.needed=function() return true end
  evidence.gui_backend="shared GUI sprites; forced in the private capture hook"
  local focused=config and config.focused
  local wanted={}
  for _,name in ipairs({"se-transfers-flow-default","se-transfers-items-recent-real","se-transfers-items-factory-history",
    "se-balance-flow-transports","se-balance-filtered-transport-history","se-focus-transports",
    "se-full-sankey-transports","se-working-factory-world","se-transfers-history-events","se-transfers-synthetic-import-markers",
    "se-transfers-history-entities","se-transfers-items-cannon-recipes",
    "se-transfers-history-rocket-loss","se-transfers-history-cannon-spill","se-transfers-history-orbit-cannon-imports",
    "se-transfers-flow-moon","se-transfers-flow-moon-orbit",
    "se-transfers-flow-by-item","se-transfers-synthetic-flow-by-item"}) do wanted[name]=true end
  local captures={}
  evidence.capture_mode=focused and "focused" or "full"
  local auto_refresh=UI.auto_refresh
  UI.auto_refresh=function()
    if not pending then auto_refresh() end
  end
  -- Give native layout and screenshot readback a full second between changes;
  -- 61 avoids replacing the production sampler's 60-tick event registration.
  script.on_nth_tick(61,function()
    if done then return end
    local p=game.connected_players[1]
    if not p then return end
    if p.controller_type==defines.controllers.cutscene then p.exit_cutscene();return end
    game.speed=4
    Native.start(p)
    if not Native.ready() then return end
    if pending then
      local f=assert(p.gui.screen.ssk_main)
      for _,root in ipairs({p.gui.screen,p.gui.center}) do
        for _,other in pairs(root.children) do if other~=f then other.visible=false end end
      end
      f.bring_to_front()
      -- A hidden graphical client may not paint between simulation updates.
      -- Force one warm-up frame before reading the final native GUI image.
      if not primed then
        game.take_screenshot{player=p,path="se-logistics-warmup/"..pending..".png",resolution={1920,1080},show_gui=true,force_render=true}
        primed=true
        return
      end
      local us=storage.ui[p.index]
      if us.tab_id=="transfers" and not us.transport_history and us.se_logistics.view=="items" then
        UI.refresh(p,true)
        local h=History.build(us.sidx,us.period,"item/iron-plate")
        local measured,estimated=0,0
        for _,sample in ipairs(h.stock) do if sample.measured then measured=measured+1 else estimated=estimated+1 end end
        evidence.stock_layout.captures=evidence.stock_layout.captures or {}
        evidence.stock_layout.captures[pending]={measured=measured,estimated=estimated,tick=game.tick,basis=storage.stock_basis,synthetic=synthetic_case()}
        local measured_targets=stock_targets(p)
        local widths={}
        for _,target in pairs(measured_targets.children) do if target.tags.measured then
          assert(target.style.minimal_width<=6 and target.style.maximal_width<=6,"Measured stock marker inherited a variable interval width")
          widths[#widths+1]=target.style.minimal_width
        end end
        evidence.stock_layout.captures[pending].measured_widths=widths
        if pending=="se-transfers-synthetic-import-markers" then
          local targets=stock_targets(p)
          local markers=0
          for _,e in pairs(targets.children) do if e.tags.import_receipt then markers=markers+1;assert(e.tags.count>0) end end
          assert(markers>0,"Known synthetic receipts lost their distinct import markers")
          evidence.import_marker_contract={synthetic=true,markers=markers,source="labelled presentation records; no public SE receipt claim"}
        end
      end
      if synthetic_case() then
        evidence.synthetic_captures[#evidence.synthetic_captures+1]=pending
      end
      evidence.toolbar_states=evidence.toolbar_states or {}
      local bar=us.tab_id=="transfers" and not us.transport_history
        and panel(p).heading or f.ssk_window_bar
      evidence.toolbar_states[pending]={title=f.ssk_window_bar.children[1].caption,visible=bar.visible,controls=#bar.children,tab=us.tab_id}
      if names[step]=="se-working-factory-world" then
        game.take_screenshot{player=p,path="se-logistics/"..pending..".png",position={x=-53,y=64},zoom=.55,
          resolution={1920,1080},show_gui=false,force_render=true}
      else
        game.take_screenshot{player=p,path="se-logistics/"..pending..".png",resolution={1920,1080},show_gui=true,force_render=true}
      end
      log("SE LOGISTICS captured="..pending)
      captures[#captures+1]=pending
      pending,primed=nil,false
      return
    end
    step=step+1
    if step>#names then
      Dense.restore()
      local us=storage.ui[p.index]
      us.tab_id="transfers";us.transport_history=nil;us.surface="nauvis";us.period=3600;us.se_logistics.view="flow";us.se_logistics.history={}
      us.se_logistics.group=nil
      UI.open(p)
      click(UI,p,tagged(panel(p).se_tabs.se_flow.viewport.body,"history",function(t)return t.direction=="exports" end))
      local records=us.se_logistics.history._records
      assert(#records>0 and records[1].sender and records[1].receiver,"No native endpoint jump pair")
      local record=records[1]
      assert(Endpoints.resolve(record.sender,p.force) and Endpoints.resolve(record.receiver,p.force))
      click(UI,p,tagged(panel(p).se_tabs.se_history.viewport.body,"panel-jump",function(t) return t.side=="sender" end))
      assert(p.surface==record.sender.surface and not UI.is_open(p),"Native sender button failed")
      UI.open(p)
      click(UI,p,tagged(panel(p).se_tabs.se_history.viewport.body,"panel-jump",function(t) return t.side=="receiver" end))
      assert(p.surface==record.receiver.surface and not UI.is_open(p),"Native receiver button failed")
      local actual=remote.call("production-flow-se-verification","check")
      assert(actual.shipments==evidence.actual.shipments and actual.cannon_effects==evidence.actual.cannon_effects,
        "Synthetic renderer data leaked into the real shipping ledger")
      log("SE ENDPOINT JUMP PASS: sender/receiver via SE public remote view")
      evidence.captures=captures;evidence.exercised_cases=names
      evidence.display_scale=p.display_scale;evidence.resolution=p.display_resolution
      helpers.write_file("se-logistics/gui.json",helpers.table_to_json(evidence),false)
      assert(p.display_scale==1 and p.display_resolution.width==1920 and p.display_resolution.height==1080)
      log("SE LOGISTICS GUI PASS")
      UI.auto_refresh=auto_refresh
      GuiPlot.needed=original_needed
      game.speed=1
      game.auto_save("se-logistics-captured")
      done=true
      return
    end
    if step==1 then
      storage.ui[p.index]={tab_id="transfers",surface="nauvis",period=3600,fx={},bal_fx={},se_logistics={view="flow"}}
      UI.open(p)
      -- Exercise all native panel styles before recording screenshots; the
      -- offline GUI mock intentionally cannot validate engine style families.
      for _,name in ipairs({"items","history","flow"}) do
        storage.ui[p.index].se_logistics.view=name
        UI.refresh(p)
      end
      log("SE TRANSFERS LAYOUT PREFLIGHT PASS: Flow, Items and History")
    end
    local us=storage.ui[p.index]
    local state=us.se_logistics
    assert(p.gui.screen.ssk_main.ssk_window_bar.ssk_surface_picker.visible,"Missing shared surface selector")
    if step<=15 then assert(panel(p).se_tabs.se_flow and panel(p).se_tabs.se_items and panel(p).se_tabs.se_history) end
    if step==1 then
      evidence.actual=remote.call("production-flow-se-verification","check")
      local q=D.query(p.force,game.surfaces.nauvis,game.tick,3600,{timing="either"})
      assert(#q.records==evidence.actual.shipments+evidence.actual.cannon_effects and #q.unpaired==0,
        "Native model lost rocket/cannon observations or left fixture shots unpaired")
      assert(#q.groups.imports>=3 and #q.groups.exports>=3,"Rich fixture needs several remote surfaces on both sides")
      assert_receipts_measured(q.records)
      assert(panel(p).se_tabs.se_flow.viewport.body.se_graph,"Missing native Flow graph")
    elseif step==2 then
      material(UI,p,"iron-plate")
      local q=D.query(p.force,game.surfaces.nauvis,game.tick,3600,{material="iron-plate",timing="either"})
      assert(#q.records>=8 and #q.groups.imports>=3 and #q.groups.exports>=3,"Iron fixture is still sparse")
      assert_receipts_measured(q.records)
    elseif step==3 then
      click(UI,p,tagged(panel(p).se_tabs.se_flow.viewport.body,"history",function(t) return t.direction=="exports" end))
      assert(state.view=="history" and state.history.route and state.history.return_view=="flow")
      assert(#state.history._records>=1 and state.history._records[1].sent[1].count>0)
      assert_receipts_measured(state.history._records)
      click(UI,p,tagged(panel(p).se_tabs.se_history.viewport.body,"panel-expand"))
      assert(state.history.expanded)
      local log=panel(p).se_tabs.se_history.viewport.body.entity_history.main.se_history_layout.se_history_log
      local manifests=log.se_shipment_1.manifest_detail.manifests
      local first=state.history._records[1]
      -- One item/lost/received table, no subtitles, measured or not.
      local sent=assert(manifests.received.manifest)
      local cell=sent.children[sent.column_count+1]
      assert(not manifests.sent and #log.se_shipment_1.manifest_detail.children==1 and sent.children[1].name=="header_1"
        and #sent.children>=sent.column_count+#first.sent and cell.received.style.horizontal_align=="right"
        and (cell.received.caption=="—")==(first.received==nil))
      evidence.shipment_manifest={items=#sent.children,columns=sent.column_count,received=received_label(first)}
      local sender=tagged(panel(p).se_tabs.se_history.viewport.body,"panel-jump",function(t) return t.side=="sender" end)
      local receiver=tagged(panel(p).se_tabs.se_history.viewport.body,"panel-jump",function(t) return t.side=="receiver" end)
      assert(sender and sender.enabled and receiver and receiver.enabled,"Known intended rocket endpoints missing")
      UI.close(p);UI.open(p)
      assert(storage.ui[p.index].se_logistics.history.expanded,"Reopening lost History expansion")
      click(UI,p,tagged(panel(p).se_tabs.se_history,"panel-return"))
      assert(state.view=="flow","History return lost its Flow caller")
      click(UI,p,tagged(panel(p).se_tabs.se_flow.viewport.body,"history",function(t) return t.direction=="exports" end))
      click(UI,p,tagged(panel(p).se_tabs.se_history.viewport.body,"panel-expand"))
    elseif step==4 then
      reset(UI,p,"history")
      state.history={method="cannon",return_view="flow"};UI.refresh(p)
      assert(#state.history._records==evidence.actual.cannon_effects and #state.history._records>=6)
      local measured=0
      for _,r in ipairs(state.history._records) do
        assert(r.method=="cannon" and r.sent and r.to and r.direction=="exports","Fixture cannon shot not paired")
        assert(r.status=="received" or r.status=="spilled" or r.status=="arrived","Fixture cannon shot unsettled")
        if r.received then measured=measured+1 end
      end
      assert(measured>0 and measured<#state.history._records,"Fixture lacks both measured and spilled cannon shots")
      assert_receipts_measured(state.history._records)
      click(UI,p,tagged(panel(p).se_tabs.se_history.viewport.body,"panel-expand"))
      local receiver=tagged(panel(p).se_tabs.se_history.viewport.body,"panel-jump",function(t) return t.side=="receiver" end)
      assert(receiver and receiver.enabled==(state.history._records[1].receiver~=nil),"Cannon receiver jump disagrees with the receipt")
    elseif step==5 then
      reset(UI,p,"history")
      view(UI,p,2,"items")
      material(UI,p,"iron-plate")
      us.period=600;UI.refresh(p)
      local root=assert(items_root(p))
      local stock_plot=root.inspector.ssk_history_scroll.ssk_history_body.ssk_history_stock_plot
      assert(stock_plot.ssk_history_gui_plot and not stock_plot.ssk_history_stock_camera,
        "SE Items stock must render outside the world camera")
      local headings=root.list.box.viewport.stack.header.columns.children
      local cells=root.list.box.viewport.stack.rows.grid.children
      assert(#headings==7 and #cells==11*7,"Manifest table lost items or shipping/consumption columns")
      for i=1,7 do assert(headings[i].style.minimal_width==cells[i].style.minimal_width,"Native header/row widths differ") end
      local favourite=assert(generic_action(root,"bal_fav",function(t)return t.key=="item/iron-plate" end))
      click(UI,p,favourite)
      assert(us.bal_favs.items["item/iron-plate"],"Items favourite did not reach shared Balance state")
      assert(items_root(p).list.box.viewport.stack.rows.grid.children[1].tags.key=="item/iron-plate")
      local usage=assert(tagged(items_root(p),"items-usage"));usage.state=false
      assert(UI.on_checked{element=usage,player_index=p.index})
      assert(state.items_history.bal_usage_breakdown==false)
      usage=assert(tagged(items_root(p),"items-usage"));usage.state=true;assert(UI.on_checked{element=usage,player_index=p.index})
      local search=items_root(p).list.strip.controls.search;search.text="iron"
      assert(UI.on_text_changed{element=search,player_index=p.index})
      assert(#items_root(p).list.box.viewport.stack.rows.grid.children==21)
      click(UI,p,tagged(items_root(p),"items-clear-search"))
      local pick=assert(tagged(items_root(p),"items-select",function(t)return t.material=="copper-plate" end));click(UI,p,pick)
      assert(state.material=="copper-plate")
      click(UI,p,tagged(items_root(p),"items-select",function(t)return t.material=="iron-plate" end))
      evidence.items_table={columns=7,manifest_items=11,header_row_widths_match=true,shared_favourites=true,
        search=true,selection=true,history_controls=true,source="actual shipping manifests and Balance rows"}
      evidence.stock_layout.provenance=evidence.actual.measured_stock
      assert(not evidence.actual.measured_stock.synthetic and evidence.actual.measured_stock.scans>=15)
    elseif step==6 then
      us.period=600;UI.refresh(p)
      local h=History.build(us.sidx,us.period,"item/iron-plate")
      local measured,estimated=0,0
      for _,sample in ipairs(h.stock) do if sample.measured then measured=measured+1 else estimated=estimated+1 end end
      assert(measured>=10 and estimated>0,"Live factory Items lost genuine completed scans or covered estimates")
      evidence.stock_layout.measured_bars,evidence.stock_layout.estimated_bars=measured,estimated
    elseif step==7 then
      click(UI,p,tagged(panel(p).se_tabs.se_items.viewport.body,"history",function(t) return t.direction=="exports" end))
      assert(state.view=="history" and state.history.return_view=="items" and state.history.material=="iron-plate")
      click(UI,p,tagged(panel(p).se_tabs.se_history,"panel-return"))
      assert(state.view=="items" and state.material=="iron-plate")
      reset(UI,p,"flow")
      material(UI,p,"iron-plate")
      click(UI,p,tagged(panel(p).se_tabs.se_flow.viewport.body,"history",function(t) return t.direction=="exports" end))
      local bucket=assert(tagged(panel(p).se_tabs.se_history.viewport.body,"panel-bucket"),"Exact sent boundary has no timeline bucket")
      local tick=bucket.tags.bucket
      click(UI,p,bucket)
      assert(state.history.bucket==tick and #state.history._records>=1)
      assert_receipts_measured(state.history._records)
    elseif step==8 then
      reset(UI,p,"flow")
      local pick=p.gui.screen.ssk_main.ssk_window_bar.ssk_surface_picker
      local selected
      for i,name in pairs(us.surface_names) do if name=="Nauvis Orbit" then selected=i end end
      assert(selected,"Transport-only orbit missing from shared surface picker")
      pick.selected_index=selected
      assert(UI.on_selection{player_index=p.index,element=pick})
      assert(us.surface=="Nauvis Orbit")
    elseif step==9 then
      reset(UI,p,"history",60)
      assert(#state.history._records==0,"Short native window should contain no transport events")
    elseif step==10 then
      us.surface="nauvis";UI.open(p)
      reset(UI,p,"flow")
      material(UI,p,"copper-plate")
    elseif step==11 then
      reset(UI,p,"history")
      state.history={material="iron-plate"};UI.refresh(p)
      assert(#state.history._records>=8,"All-route iron History is still sparse")
    elseif step==12 then
      evidence.synthetic_layout=Dense.install(p,game.surfaces.nauvis)
      evidence.synthetic_layout.initial_records=evidence.synthetic_layout.records
      reset(UI,p,"flow",600)
      material(UI,p,"iron-plate")
      local q=D.query(p.force,p.surface,game.tick,600,{material="iron-plate"})
      assert(#q.groups.imports==3 and #q.groups.exports==3)
      for _,side in ipairs({"imports","exports"}) do for _,group in ipairs(q.groups[side]) do assert(#group.methods==2) end end
    elseif step==13 then
      reset(UI,p,"history",600)
      state.history={material="iron-plate"};UI.refresh(p)
      assert(#state.history._records==48 and state.history._pages>=3)
      local imports,exports=0,0
      for _,record in ipairs(state.history._records) do
        if record.direction=="imports" and record.received then imports=imports+1 end
        if record.direction=="exports" and record.sent then exports=exports+1 end
      end
      assert(imports>0 and exports>0,"Dense signed History lost an independent quantity boundary")
      click(UI,p,tagged(panel(p).se_tabs.se_history.viewport.body,"panel-expand"))
    elseif step==14 then
      click(UI,p,tagged(panel(p).se_tabs.se_history.viewport.body,"panel-page",function(t) return t.delta==1 end))
      assert(state.history.page==2)
    elseif step==15 then
      Dense.add_overflow()
      reset(UI,p,"flow",600)
      material(UI,p,"iron-plate")
      for _,side in ipairs({"imports","exports"}) do
        assert(state[side.."_pages"]>1)
        click(UI,p,tagged(panel(p).se_tabs.se_flow.viewport.body,"page",function(t) return t.side==side and t.delta==1 end))
        assert(state[side.."_page"]==2)
      end
    elseif step==16 then
      Dense.restore()
      us.transport_history=nil;us.tab_id="balance";us.surface="nauvis";us.period=3600;us.bal_mode="flow"
      us.bal_fx={view="focus",neighborhood=true,focus_steps=1,focus="item/iron-plate",sel="item/iron-plate",
        renderer="poly",heights="linear",lines="curves",live=true}
      UI.open(p);graph_evidence(p,"balance")
    elseif step==17 then
      local target=assert(generic_action(p.gui.screen.ssk_main,"transport_history",function(t)
        return t.provider=="se" and t.material=="iron-plate" and t.direction=="exports" end))
      click(UI,p,target)
      local transfer=assert(us.transport_history)
      assert(us.tab_id=="transfers" and transfer.origin.tab=="balance" and transfer.history.material=="iron-plate"
        and transfer.history.direction=="exports" and us.period==3600)
      assert(#transfer.history._records>=1,"Clicked graph boundary lost its shipment records")
      assert_receipts_measured(transfer.history._records)
      local body=assert(find(p.gui.screen.ssk_main,function(e) return e.name=="ssk_transport_history" end))
      click(UI,p,tagged(body,"panel-expand"))
      evidence.graph_history={origin="balance",material=transfer.history.material,direction=transfer.history.direction,
        provider=transfer.provider,records=#transfer.history._records,received=received_label(transfer.history._records[1])}
    elseif step==18 then
      click(UI,p,generic_action(p.gui.screen.ssk_main,"transport_history_return"))
      assert(us.tab_id=="balance" and not us.transport_history and us.surface=="nauvis" and us.period==3600
        and us.bal_fx.focus=="item/iron-plate","Filtered History return lost caller state")
      us.tab_id="focus"
      us.fx={view="focus",focus_steps=2,focus="item/iron-plate",sel="item/iron-plate",renderer="poly",heights="linear",lines="curves",live=true}
      UI.open(p);graph_evidence(p,"focus")
    elseif step==19 then
      us.tab_id="sankey";us.view="detail";us.renderer="poly";us.lines="curves";us.heights="linear";us.layout="clean"
      us.sel="item/iron-plate";us.preset="all";us.collapsed={};us.hidden={};us.tier_lo,us.tier_hi=nil,nil
      UI.open(p);graph_evidence(p,"sankey")
    elseif step==20 then
      assert(p.surface==game.surfaces.nauvis,"Factory overview player is on another surface")
      evidence.factory_world={synthetic=false,surface=p.surface.name,position={x=-53,y=64},zoom=.55,
        factory=evidence.actual.factory,source="live working test world"}
    elseif step==21 then
      us.tab_id="transfers";us.transport_history=nil;us.surface="nauvis";us.period=3600
      state.view="history";state.history={material="iron-plate"}
      UI.open(p)
      local axis=assert(find(panel(p).se_tabs.se_history,function(e) return e.tags.transfer_axis end))
      assert(axis.type=="switch" and axis.switch_state=="left")
      axis.switch_state="right"
      assert(UI.on_switch{element=axis,player_index=p.index})
      assert(state.history.axis=="events" and #state.history._exchanges>4)
      local targets=panel(p).se_tabs.se_history.viewport.body.entity_history.main.se_history_layout.se_history_plot.se_history_chart.se_panel_targets
      local previous,count=nil,0
      for _,e in pairs(targets.children) do if e.tags.se_logistics=="panel-exchange" then
        if previous then assert(e.style.left_margin-previous==24,"Exchange spacing is not compact") end
        previous=e.style.left_margin;count=count+1
      end end
      assert(count>4)
      assert(previous+22==targets.style.minimal_width-17,"Newest exchange is not aligned to the plot's right edge")
      evidence.exchange_axis={provider="se",axis="events",slot_pixels=24,visible_exchanges=count,synthetic=false}
    elseif step==22 then
      evidence.import_marker_fixture=Dense.install(p,game.surfaces.nauvis)
      reset(UI,p,"items",600);material(UI,p,"iron-plate")
    elseif step==23 then
      Dense.restore()
      reset(UI,p,"history",600)
      local root=panel(p).se_tabs.se_history.viewport.body.entity_history
      local hs=state.history
      -- The selected ten-minute window can lose an older shipment while the
      -- capture runs. Compare with the provider at this tick, then verify that
      -- selecting an entity and returning to Total preserves that scope.
      local total=#D.query(p.force,game.surfaces.nauvis,game.tick,600,{timing="either"}).records
      assert(total>1 and hs.entity==nil and root.sidebar.box.total.children[1].toggled and #hs._records==total,
        ("History must default to Total (%d/%d records)"):format(#hs._records,total))
      local pick=assert(find(root.sidebar.box.scroll,function(e)
        local key=e.tags.history_entity
        local count=key and hs._entity_counts[key]
        return count and count>0 and count<total
      end),"Expected an entity with a proper subset of the selected shipment window")
      local selected_key=pick.tags.history_entity
      click(UI,p,pick)
      assert(hs.entity==selected_key and #hs._records>0 and #hs._records<total,"Entity click did not narrow real History")
      local focused=#hs._records
      local star=assert(find(root.sidebar.box.scroll,function(e)return e.tags.history_entity_favourite==selected_key end))
      click(UI,p,star);assert(us.transport_entity_favs[selected_key])
      local search=root.sidebar.strip.controls.search;search.text="cannon"
      assert(UI.on_text_changed{element=search,player_index=p.index})
      assert(root.sidebar.strip.controls.search==search)
      local clear=assert(find(root.sidebar.strip.controls,function(e)return e.tags.history_entity_clear_search end));click(UI,p,clear)
      click(UI,p,root.sidebar.box.total.children[1])
      assert(hs.entity==nil and #hs._records==total)
      evidence.entity_history={default="Total",total_records=total,focused_records=focused,selected_key=selected_key,
        groups=true,search=true,independent_favourites=true,synthetic=false}
    elseif step==24 then
      reset(UI,p,"items",600);state.method="cannon";UI.refresh(p)
      local cells=items_root(p).list.box.viewport.stack.rows.grid.children
      assert(#cells==7 and state.material=="iron-plate" and cells[3].caption=="—" and cells[4].caption=="—",
        "Cannon recipe should identify the item without inventing manifests")
      evidence.cannon_recipe_items={rows=1,material=state.material,source="public configured recipes",synthetic=false}
    elseif step==25 or step==26 then
      -- Expanded real shipments: a measured rocket loss, then a spilled cannon
      -- shot narrowed to its sender so the row is near the top of the log.
      reset(UI,p,"history")
      state.history=step==25 and {method="rocket",direction="exports",material="iron-plate",return_view="flow"}
        or {method="cannon",return_view="flow"}
      UI.refresh(p)
      local function total(items) local n=0;for _,item in ipairs(items or {}) do n=n+item.count end;return n end
      local function pick()
        for i,r in ipairs(state.history._records) do
          if i<=3 and (step==25 and r.received and total(r.received)<total(r.sent) or step==26 and r.status=="spilled") then return i,r end
        end
      end
      local index,record=pick()
      if step==26 and not index then
        local function sidebar() return panel(p).se_tabs.se_history.viewport.body.entity_history.sidebar.box.scroll end
        local keys={}
        local function collect(e)
          if e.tags and e.tags.history_entity then keys[#keys+1]=e.tags.history_entity end
          for _,child in pairs(e.children) do collect(child) end
        end
        collect(sidebar())
        for _,key in ipairs(keys) do
          click(UI,p,assert(find(sidebar(),function(e) return e.tags and e.tags.history_entity==key end)))
          index,record=pick()
          if index then break end
        end
      end
      assert(index,step==25 and "Fixture lacks a measured rocket loss" or "Fixture lacks a spilled cannon shot")
      click(UI,p,tagged(panel(p).se_tabs.se_history.viewport.body,"panel-expand",function(t) return t.index==index end))
      local log=panel(p).se_tabs.se_history.viewport.body.entity_history.main.se_history_layout.se_history_log
      local detail=assert(log["se_shipment_"..index].manifest_detail,"Shipment did not expand")
      -- No subtitles, departure or outcome lines; the outcome explains a "—" in its tooltip.
      local grid=assert(detail.manifests.received.manifest)
      local cell=grid.children[grid.column_count+1]
      assert(#detail.children==1 and not detail.manifests.sent,"Expanded shipment must hold only its manifest table")
      if step==25 then
        assert(cell.tags.lost==total(record.sent)-total(record.received)
          and cell.lost.caption=="−"..cell.tags.lost and cell.received.caption==tostring(total(record.received)),
          "Rocket loss cell must read item, negative loss, received")
      else
        assert(cell.received.caption=="—" and cell.lost.caption=="—" and cell.tags.sent==total(record.sent),
          "Spilled shot must keep its sent amount and read received unknown")
        -- The missing catcher is flagged on the main row, not in the detail.
        local warning=log["se_shipment_"..index].children[1].no_catcher
        assert(warning and warning.children[1].sprite=="utility/warning_icon","Spilled shot lacks its main-row warning")
        assert(not detail.no_catcher and not detail.manifests.no_catcher,"Catcher warning leaked into the detail")
      end
      evidence[step==25 and "rocket_loss" or "cannon_spill"]={row=index,status=record.status,sent=total(record.sent),
        received=record.received and total(record.received) or "unknown",landed_tick=record.landed_tick,synthetic=false}
    elseif step==27 then
      -- Receiving side: measured chest receipts draw blue; the spill draws
      -- the quantity-unavailable marker instead of a full dispatch bar.
      us.surface="Nauvis Orbit";UI.open(p)
      reset(UI,p,"history")
      state.history={method="cannon",direction="imports",return_view="flow"};UI.refresh(p)
      local spilled,measured=0,0
      for _,r in ipairs(state.history._records) do
        assert(r.direction=="imports" and r.method=="cannon","Orbit cannon History escaped its filter")
        local _,kind,count=Exchanges.observation(r)
        if r.status=="spilled" then
          assert(kind=="received" and count==nil,"Spilled shot drawn as a quantity");spilled=spilled+1
        elseif r.received then
          assert(kind=="received" and count==100,"Measured chest receipt not drawn");measured=measured+1
        end
      end
      assert(spilled==1 and measured>=1,"Orbit cannon imports lack a spill and a measured receipt")
      -- Expand the newest measured shot: a whole cannon receipt reads a zero loss.
      local whole
      for i,r in ipairs(state.history._records) do if r.received then whole=i;break end end
      click(UI,p,assert(tagged(panel(p).se_tabs.se_history.viewport.body,"panel-expand",function(t) return t.index==whole end)))
      local log=panel(p).se_tabs.se_history.viewport.body.entity_history.main.se_history_layout.se_history_log
      local grid=assert(log["se_shipment_"..whole].manifest_detail.manifests.received.manifest)
      local cell=grid.children[grid.column_count+1]
      assert(cell.lost.caption=="0" and cell.received.caption=="100","Whole cannon receipt must read zero loss")
      assert(not log["se_shipment_"..whole].children[1].no_catcher,"A caught cannon shot must not warn")
      evidence.orbit_cannon_receipt_cell={row=whole,lost=0,received=100,synthetic=false}
      evidence.orbit_cannon_imports={records=#state.history._records,measured=measured,spilled=spilled,synthetic=false}
    elseif step==28 or step==29 then
      -- Flow centre card on the fixture's moon and its orbit: SE zone details,
      -- and for the moon its top resources by SE's map generation estimate.
      local wanted_type=step==28 and "moon" or "orbit"
      local target
      for _,s in pairs(game.surfaces) do
        local ok,zone=pcall(remote.call,"space-exploration","get_zone_from_surface_index",{surface_index=s.index})
        if ok and type(zone)=="table" and zone.type==wanted_type and s.name~="Nauvis Orbit" then
          if wanted_type=="moon" or zone.parent_index and remote.call("space-exploration","get_zone_from_zone_index",{zone_index=zone.parent_index}).type=="moon" then
            target=s;break
          end
        end
      end
      assert(target,"Fixture lacks its "..wanted_type.." surface")
      us.surface=target.name;UI.open(p)
      reset(UI,p,"flow",3600)
      local card=panel(p).se_tabs.se_flow.viewport.body.se_graph.se_center_wrap.se_center
      assert(card.se_zone and card.se_zone.se_type,"Zone details missing on "..target.name)
      for _,e in ipairs(card.children) do assert(e.name~="se_stock" and e.name~="se_stock_row","Stored items count returned") end
      local resources={}
      if step==28 then
        assert(card.se_zone.se_parent_planet and card.se_zone.se_parent_star,"Moon card lacks its planet and star")
        local grid=assert(card.se_resources,"Moon card lacks its top resources")
        assert(#grid.children>=6 and #grid.children<=18 and #grid.children%3==0,"Moon resource table malformed")
        for i=1,#grid.children/3-1 do resources[i]=grid["se_resource_"..i].caption end
      else
        assert(not card.se_resources,"Orbit card must not list resources")
        assert(card.se_zone.se_parent_moon and card.se_zone.se_parent_planet and card.se_zone.se_parent_star,
          "Moon orbit card lacks its moon, planet and star")
      end
      evidence[step==28 and "flow_moon_card" or "flow_moon_orbit_card"]={surface=target.name,rows=#card.se_zone.children,
        resources=#resources,synthetic=false}
    elseif step==30 then
      us.surface="nauvis";UI.open(p)
      reset(UI,p,"flow",3600);group_by(UI,p,state,"items")
      evidence.flow_by_item={real=item_rows(p),synthetic=false}
    elseif step==31 then
      Dense.install(p,game.surfaces.nauvis)
      reset(UI,p,"flow",600);group_by(UI,p,state,"items")
      evidence.flow_by_item.synthetic=item_rows(p)
    end
    -- Reopen with the final selection to settle native tab/dropdown layout and
    -- synchronize the shared Period control after direct fixture state changes.
    UI.open(p)
    if synthetic_case() then
      p.gui.screen.ssk_main.ssk_window_bar.children[1].caption={"","Production Flow · SYNTHETIC TEST DATA"}
    end
    suppress_tooltips(p.gui.screen.ssk_main)
    if not focused or wanted[names[step]] then pending=names[step] end
  end)
end
return C
