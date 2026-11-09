-- Injected into an isolated copy only. Never included in release packages.
local T = {}
local mode = require("scripts.save_test_mode")
local SK = require("scripts.sankey_ui")
local Model = require("scripts.model")
local View = require("scripts.view")
local Diag = require("scripts.diag")
local ChestStock=require("scripts.chest_stock")
local Balance=require("scripts.balance")
local History=require("scripts.history")
local Transfers=require("scripts.transfers")
local start, step, capture = nil, 0, nil
local selection
local captures, skipped, products, usage_labels = {}, {}, {}, {}

local cases = {
  {name="nauvis-balance", surface="nauvis", tab="balance"},
  {name="nauvis-overview", surface="nauvis", tab="sankey", view="overview"},
  {name="nauvis-items", surface="nauvis", tab="sankey", view="detail"},
  {name="nauvis-inputs", surface="nauvis", tab="balance", focus="item/iron-plate", depth=3},
  {name="vulcanus-overview", surface="vulcanus", tab="sankey", view="overview"},
  {name="fulgora-overview", surface="fulgora", tab="sankey", view="overview"},
  {name="gleba-overview", surface="gleba", tab="sankey", view="overview"},
  {name="aquilo-overview", surface="aquilo", tab="sankey", view="overview"},
  {name="nauvis-focus", surface="nauvis", tab="focus", focus="item/electronic-circuit"},
  {name="platform-overview", surface="platform-6", tab="sankey", view="overview"},
  {name="nauvis-advanced", surface="nauvis", tab="sankey", view="overview", advanced=true},
  {name="nauvis-sprites", surface="nauvis", tab="sankey", view="overview", renderer="sprites"},
}
if mode == "balance" then
  cases = {
    {name="balance-iron", surface="nauvis", tab="balance", focus="item/iron-plate", depth=3},
    {name="balance-circuit", surface="nauvis", tab="balance", focus="item/electronic-circuit", depth=2},
    {name="balance-steel", surface="nauvis", tab="balance", focus="item/steel-plate", depth=1},
    {name="balance-condensation", surface="vulcanus", tab="balance", focus="fluid/water", depth=1},
    {name="balance-steam", surface="vulcanus", tab="balance", focus="fluid/steam", depth=1},
    {name="balance-acid", surface="vulcanus", tab="balance", focus="fluid/sulfuric-acid", depth=1},
    {name="balance-molten-iron", surface="vulcanus", tab="balance", focus="fluid/molten-iron", depth=1},
    {name="balance-lubricant", surface="vulcanus", tab="balance", focus="fluid/lubricant", depth=1},
    {name="balance-petroleum", surface="nauvis", tab="balance", focus="fluid/petroleum-gas", depth=1},
    {name="balance-ice-melting", surface="platform-6", tab="balance", focus="fluid/water", depth=1},
    {name="balance-condensation-pinned", surface="vulcanus", tab="balance", focus="fluid/water", depth=1, pin="fluid/steam#input"},
    {name="balance-condensation-proportional", surface="vulcanus", tab="balance", focus="fluid/water", depth=1, heights="linear"},
  }
end
if mode == "full" then
  cases={
    {name="full-nauvis",surface="nauvis",tab="sankey",view="overview"},
    {name="full-vulcanus",surface="vulcanus",tab="sankey",view="overview"},
    {name="full-fulgora",surface="fulgora",tab="sankey",view="overview"},
    {name="full-gleba",surface="gleba",tab="sankey",view="overview"},
    {name="full-aquilo",surface="aquilo",tab="sankey",view="overview"},
    {name="full-platform",surface="platform-6",tab="sankey",view="overview"},
    {name="full-platform-copper",surface="platform-6",tab="sankey",view="detail",preset="roots:item/copper-plate"},
    {name="full-vulcanus-copper",surface="vulcanus",tab="sankey",view="detail",preset="roots:item/copper-plate"},
    {name="full-nauvis-oil",surface="nauvis",tab="sankey",view="detail",preset="super:oil"},
    {name="full-vulcanus-oil",surface="vulcanus",tab="sankey",view="detail",preset="super:oil"},
    {name="full-nauvis-items",surface="nauvis",tab="sankey",view="detail"},
    {name="full-oil-pinned",surface="nauvis",tab="sankey",view="detail",preset="super:oil",pin="fluid/petroleum-gas"},
    {name="full-nauvis-sprites",surface="nauvis",tab="sankey",view="overview",renderer="sprites"},
    {name="full-nauvis-proportional",surface="nauvis",tab="sankey",view="overview",heights="linear"},
    {name="focus-circuit",surface="nauvis",tab="focus",focus="item/electronic-circuit"},
    {name="focus-condensation",surface="vulcanus",tab="focus",focus="fluid/water"},
    {name="focus-petroleum",surface="nauvis",tab="focus",focus="fluid/petroleum-gas"},
    {name="full-balance-regression",surface="vulcanus",tab="balance",focus="fluid/water",depth=1},
    {name="balance-iron-usage",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1},
    {name="balance-steam-usage",surface="vulcanus",tab="balance",focus="fluid/steam",depth=1},
  }
end

if mode == "focus" then
  cases={
    {name="focus-petroleum-before",surface="nauvis",tab="focus",focus="fluid/petroleum-gas"},
    {name="focus-wood",surface="nauvis",tab="focus",pick="item/wood",empty=true},
    {name="focus-back",surface="nauvis",tab="focus",back=true},
    {name="focus-wood-sprites",surface="nauvis",tab="focus",pick="item/wood",empty=true,renderer="sprites"},
    {name="focus-unrecorded-fluid",surface="nauvis",tab="focus",pick="fluid/lithium-brine",empty=true},
  }
end

if mode == "selection" then
  cases={
    {name="selection-priority",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1},
    {name="selection-details",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,details=true},
    {name="selection-groups",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,groups=true},
  }
end

if mode == "picker" then
  cases={
    {name="picker-focus-browse",surface="nauvis",tab="focus",focus="item/iron-plate",query=""},
    {name="picker-fluid-group",surface="nauvis",tab="focus",focus="fluid/water",query="",group_material="fluid/water"},
    {name="picker-scroll-results",surface="nauvis",tab="focus",focus="item/iron-plate",query="e",expect_scroll=true},
    {name="picker-focus-iron-catalog",surface="nauvis",tab="focus",focus="item/iron-plate",query="iron"},
    {name="picker-balance-list",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,pick="fluid/water"},
    {name="picker-balance-groups",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,pick="fluid/water",groups=true,
      favs={items={["item/steel-plate"]=true},groups={["plates"]=true}}},
    {name="picker-balance-scroll-bottom",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,pick="fluid/water",bottom=true},
    {name="picker-balance-options",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,pick="fluid/water",options=true},
    {name="picker-focus-options",surface="nauvis",tab="focus",focus="item/electronic-circuit",pick="item/wood",options=true},
    {name="picker-focus-catalog",surface="nauvis",tab="focus",focus="item/electronic-circuit",query="wood"},
    {name="picker-focus-history",surface="nauvis",tab="focus",focus="item/electronic-circuit",pick="item/wood"},
    {name="picker-focus-cleared",surface="nauvis",tab="focus",focus="item/electronic-circuit",pick="item/wood",clear=true},
    {name="picker-focus-wood-empty",surface="nauvis",tab="focus",focus="item/electronic-circuit",pick="item/wood",stay_pick=true},
    {name="picker-focus-six-visits",surface="nauvis",tab="focus",focus="item/electronic-circuit",pick="item/wood",six_visits=true},
    {name="picker-full-controls",surface="nauvis",tab="sankey",view="detail"},
    {name="picker-full-settings",surface="nauvis",tab="sankey",view="detail",advanced=true},
  }
end

if mode == "scroll" then
  cases={
    {name="balance-scroll-top",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1},
    {name="balance-scroll-bottom",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,bottom=true},
    {name="balance-scroll-details",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,bottom=true,details=true},
    {name="balance-groups-top",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,groups=true},
    {name="balance-groups-details",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,groups=true,details=true},
    {name="balance-scroll-groups",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,bottom=true,groups=true},
    {name="balance-beta-water",surface="vulcanus",tab="balance",focus="fluid/water",depth=1},
    {name="balance-favourites",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,groups=true,
      favs={items={["item/steel-plate"]=true,["item/stone"]=true},groups={["plates"]=true}}},
  }
end

if mode=="names" then
  cases={
    {name="full-platform-copper",surface="platform-6",tab="sankey",view="detail",preset="roots:item/copper-plate"},
    {name="full-vulcanus-copper",surface="vulcanus",tab="sankey",view="detail",preset="roots:item/copper-plate"},
  }
end

if mode=="audit" then
  cases={{name="stock-audit",surface="nauvis",tab="balance",focus="item/steel-plate",depth=1}}
end

local audit_fixture
local function audit_stock(Sampler)
  local C=ChestStock
  local surface=game.create_surface("chest-stock-audit",{width=64,height=64,default_enable_all_autoplace_controls=false})
  surface.request_to_generate_chunks({0,0},1);surface.force_generate_chunk_requests()
  local tiles={};for y=-10,10 do for x=-10,10 do tiles[#tiles+1]={name="refined-concrete",position={x,y}} end end
  surface.set_tiles(tiles)
  local expected=0
  for i,name in ipairs({"wooden-chest","iron-chest","steel-chest","requester-chest","buffer-chest","storage-chest","passive-provider-chest","active-provider-chest"}) do
    local chest=surface.create_entity{name=name,position={-8+2*i,0},force="player"}
    assert(chest and chest.insert{name="steel-plate",count=i,quality="normal"}==i)
    assert(chest.insert{name="steel-plate",count=2*i,quality="rare"}==2*i)
    C.add(chest);expected=expected+3*i
  end
  C.rescan() -- Include the entire fixture in a fresh scan.
  audit_fixture={surface=surface.index,expected=expected}
end
local function finish_audit(Sampler)
  local measured=Sampler.stock(audit_fixture.surface)["item/steel-plate"]
  assert(measured and measured.count==audit_fixture.expected,"Native chest stock fixture mismatch")
  local report={tick=game.tick,fixture=audit_fixture,measured=measured,types={},surfaces={},sampler=Sampler.stock_status()}
  for _,surface in pairs(game.surfaces) do
    local n=0
    for _,chest in pairs(surface.find_entities_filtered{type={"container","logistic-container"},force="player"}) do
      report.types[chest.name]=(report.types[chest.name] or 0)+1;n=n+1
    end
    if n>0 then report.surfaces[surface.name]={chests=n,stock=Sampler.stock(surface.index)} end
  end
  helpers.write_file("save-test/stock-audit.json",helpers.table_to_json(report),false)
  log("STOCK AUDIT all eight chest types and mixed qualities: "..measured.count.." items")
end

if mode=="ux" then
  cases={
    {name="ux-water",surface="vulcanus",tab="balance",focus="fluid/water",depth=1},
    {name="ux-stock",surface="nauvis",tab="balance",focus="item/steel-plate",depth=1,details=true},
    {name="ux-copper",surface="vulcanus",tab="balance",focus="item/copper-plate",depth=1},
    {name="ux-steam",surface="vulcanus",tab="balance",focus="fluid/steam",depth=1},
    {name="ux-list-update",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,update_list=true},
    {name="ux-help-basics",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,help_tab=1},
    {name="ux-help-stock",surface="nauvis",tab="balance",focus="item/steel-plate",depth=1,help_tab=2},
    {name="ux-help-alerts",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,help_tab=3},
    {name="ux-recent",surface="vulcanus",tab="balance",focus="fluid/steam",depth=1,recent=true},
  }
elseif mode=="warmup" then
  cases={{name="ux-warmup",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1}}
elseif mode=="diagnostics" then
  cases={
    {name="diagnostics-watch",surface="nauvis",tab="balance",focus="item/iron-plate",watch=true},
    {name="diagnostics-biggest-deficit",surface="nauvis",tab="balance",focus="item/iron-plate",sort=3},
    {name="diagnostics-soonest-empty",surface="nauvis",tab="balance",focus="item/iron-plate",sort=4},
    {name="diagnostics-watch-warning",surface="nauvis",tab="balance",focus="item/iron-plate",watch_warning=true},
    {name="diagnostics-machine-status",surface="ssk-diagnostics-fixture",tab="balance",focus="item/iron-gear-wheel",machine="status"},
    {name="diagnostics-machine-preview",surface="ssk-diagnostics-fixture",tab="balance",focus="item/iron-gear-wheel",machine="preview"},
  }
elseif mode=="history-view" then
  cases={
    {name="electronic-circuit-flow",surface="nauvis",tab="balance",focus="item/electronic-circuit",flow_only=true},
    {name="electronic-circuit-history",surface="nauvis",tab="balance",focus="item/electronic-circuit"},
    {name="history-rates-and-stock",surface="nauvis",tab="balance",focus="item/iron-plate"},
    {name="history-totals",surface="nauvis",tab="balance",focus="item/iron-plate",breakdown=false},
    {name="history-long-window",surface="nauvis",tab="balance",focus="item/iron-plate",long_period=true},
    {name="history-selected-fluid",surface="vulcanus",tab="balance",focus="fluid/water"},
  }
elseif mode=="transfer-view" then
  cases={{name="transfers-delivered-cargo",surface="nauvis",tab="transfers"}}
end
local after_capture, diagnostic_machine
local stock_fixture, transfer_fixture
local function find_ui(el,action,tag)
  if el.tags and el.tags[tag or "ssk_ui"]==action then return el end
  for _,child in pairs(el.children) do local x=find_ui(child,action,tag);if x then return x end end
end

local function find_node(element)
  if element.tags and element.tags.ssk_sk == "node" then return element end
  for _, child in pairs(element.children) do
    local found = find_node(child)
    if found then return found end
  end
end

local function find_action(element, action, key)
  if element.tags and element.tags.ssk_sk==action and (not key or element.tags.key==key) then return element end
  for _, child in pairs(element.children) do
    local found=find_action(child,action,key); if found then return found end
  end
end

local function find_scope(element)
  if element.tags and element.tags.ssk_ui=="surface" then return element end
  for _,child in pairs(element.children) do local found=find_scope(child); if found then return found end end
end

local function find_named(element, name)
  if element.name==name then return element end
  for _,child in ipairs(element.children) do
    local result=find_named(child,name)
    if result then return result end
  end
end

local function material_row(element,key)
  if element.tags.ssk_ui=="focus_item" and element.tags.key==key then return element end
  for _,child in ipairs(element.children) do
    local row=material_row(child,key)
    if row then return row end
  end
end

local function exercise_history(UI, player, root, us, case)
  local split=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split
  local list=split.ssk_balance_table.ssk_bal_root
  local items=list.ssk_bal_list.ssk_bal_items
  local function click(element)
    assert(UI.on_click{player_index=player.index,element=assert(element)},"History action was not handled")
  end
  local tabs=split.ssk_balance_focus.ssk_balance_inspector_tabs
  assert(tabs.type=="tabbed-pane" and #tabs.tabs==2,"Balance inspector must use native tabs")
  local function select_tab(index, expected)
    tabs.selected_tab_index=index
    assert(UI.on_tab_changed{player_index=player.index,element=tabs},"Inspector tab change was not handled")
    assert(us.bal_mode==expected and tabs.selected_tab_index==index,"Inspector tab selection did not persist")
  end
  select_tab(1,"flow")
  local flow=tabs.ssk_balance_flow_panel
  assert(find_node(flow),"Flow did not render for the same material")
  if case.name=="electronic-circuit-history" then
    local fx=SK.balance_state(us)
    click(find_action(flow,"node","item/copper-cable#input"))
    assert(fx.focus=="item/copper-cable" and fx.focus_hist[#fx.focus_hist]==case.focus,
      "Balance Flow node clicks must still select and record visits")
    click(material_row(items,case.focus))
  end
  local flow_slot=assert(find_named(flow,"ssk_material_slot"))
  select_tab(2,"history")
  local panel=tabs.ssk_history_panel
  local history_slot=assert(find_named(panel,"ssk_material_slot"))
  assert(flow_slot.locked and history_slot.locked and flow_slot.elem_value.name==history_slot.elem_value.name,
    "Flow and History must show the same read-only material")
  local rate_plot=assert(find_named(panel,"ssk_history_camera"),"History needs a native plot camera").parent
  local net_plot=assert(find_named(panel,"ssk_history_net_camera"),"History needs a separate net rate plot").parent
  local order={}
  for i,section in ipairs(rate_plot.parent.children) do order[section.name]=i end
  assert(order.ssk_history_rate_plot<order.ssk_history_net_section
    and order.ssk_history_net_section<order.ssk_history_stock_plot,
    "History must show Rate history, Net rate, then Chest stock")
  local rate_hover=assert(rate_plot.ssk_history_tooltips.children[1],"The rate plot needs hover targets")
  local net_hover=assert(net_plot.ssk_history_tooltips.children[1],"The net plot needs hover targets")
  assert(not rate_hover.ignored_by_interaction and rate_hover.tooltip==net_hover.tooltip
    and rate_hover.tooltip:find("Made",1,true) and rate_hover.tooltip:find("Used",1,true)
    and rate_hover.tooltip:find("Net",1,true),"Rate and net plots must share interactive bucket values")
  assert(SK.balance_state(us).focus==case.focus and items.valid,"History lost the Balance selection or scroller")
  if case.name=="history-rates-and-stock" then
    click(material_row(items,"item/copper-plate"))
    assert(SK.balance_state(us).focus=="item/copper-plate" and items.valid,"Selecting a material lost History or the Balance list")
    click(material_row(items,case.focus))
    assert(tabs.ssk_history_panel==panel and tabs.selected_tab_index==2,"Selecting a material rebuilt History")
  end
  local mode_control=assert(find_ui(panel,"history_usage"),"History usage toggle is missing")
  mode_control.state=case.breakdown~=false
  assert(UI.on_checked{player_index=player.index,element=mode_control},"History usage change was not handled")
  assert(find_named(panel,"ssk_history_uses").visible==mode_control.state,"Wrong History breakdown state")
  local function choose_period(index)
    local period=assert(find_ui(root,"period"))
    period.selected_index=index
    assert(UI.on_selection{player_index=player.index,element=period},"History period change was not handled")
  end
  if case.long_period then
    choose_period(4)
    assert(us.period==36000,"History must use the selected ten-hour period")
    items=split.ssk_balance_table.ssk_bal_root.ssk_bal_list.ssk_bal_items
  end
  UI.refresh(player,true)
  assert(items.valid and mode_control.valid,"History refresh rebuilt a selector or the scrolled table")
  local history=History.build(us.sidx,us.period,case.focus)
  local measured, estimated=0,0
  for _,sample in ipairs(history.stock) do
    if sample.measured then measured=measured+1 else estimated=estimated+1 end
  end
  if history.stock_supported then
    assert(measured>0,"Item History must render measured stock")
    if case.focus=="item/iron-plate" then
      assert(measured>=2 and (case.long_period or estimated>0),"Iron plate must render measured and estimated stock")
      if case.name=="history-rates-and-stock" then
        assert(history.stock[#history.stock].joined,"The Iron Plate capture needs rates through the latest completed scan")
      end
    end
    assert(#history.usage_keys>0,"Active items must have usage history")
    local stock_plot=assert(find_named(panel,"ssk_history_stock_camera"),"Item History needs a native stock plot").parent
    local stock_hover=assert(stock_plot.ssk_history_tooltips.children[1],"The stock plot needs hover targets")
    assert(not stock_hover.ignored_by_interaction and stock_hover.tooltip:find("stock",1,true),"Stock tooltips must be interactive")
  else
    assert(not history.stock_supported and #history.stock==0,"Fluid must not show measured chest stock")
  end
  after_capture=function()
    if case.long_period then
      choose_period(2)
      items=split.ssk_balance_table.ssk_bal_root.ssk_bal_list.ssk_bal_items
    end
    select_tab(1,"flow")
    assert(items.valid and find_node(tabs.ssk_balance_flow_panel),"Returning to Flow lost the selection or list")
  end
  log("BALANCE HISTORY PASS "..case.name.." measured="..measured.." estimated="..estimated)
end

local function send_fixture_cargo(fixture, name, count, offset)
  local ground, force=game.surfaces.nauvis,game.forces.player
  local spawn=force.get_spawn_position(ground)
  local position=assert(ground.find_non_colliding_position("cargo-pod-container",{spawn.x+offset,spawn.y},40,1))
  local pod=assert(fixture.hub.create_cargo_pod())
  assert(pod.get_inventory(defines.inventory.cargo_unit).insert{name=name,count=count}==count,"Transfer fixture pod is too small")
  pod.cargo_pod_destination={type=defines.cargo_destination.surface,surface=ground,position=position,land_at_exact_position=true}
end

local function start_transfer_fixture()
  local ground, force=game.surfaces.nauvis, game.forces.player
  local platform=assert(force.create_space_platform{
    name="Fixture Freighter",planet="nauvis",starter_pack="space-platform-starter-pack"})
  local hub=assert(platform.apply_starter_pack(true))
  platform.space_location="nauvis"
  local fixture={hub=hub}
  send_fixture_cargo(fixture,"copper-plate",50,20)
  return fixture
end

local function exercise_transfers(UI, player, root, us)
  local hub=transfer_fixture.hub
  local from,to
  local amounts={}
  for _,entry in ipairs(Transfers.query(player.force,game.tick,us.period).rows) do
    if entry.from.surface==hub.surface and entry.to.surface==game.surfaces.nauvis then
      from,to=entry.from.id,entry.to.id
      amounts[entry.material]=entry.count
    end
  end
  assert(from and to and amounts["copper-plate"]==50 and amounts["steel-plate"]==41,
    "Native cargo arrivals did not produce exact transfer totals")
  local panel=root.ssk_inner.ssk_tabs.content_transfers
  assert(not root.ssk_window_bar.ssk_surface_picker.visible,"Transfers needs its own origin and destination scope")
  local function select(name,key)
    local picker=assert(find_named(panel,name),"Transfer filter is missing")
    local index=1
    if key then
      index=nil
      for i,choice in pairs(picker.tags.keys) do
        if choice==key then index=i; break end
      end
      assert(index,"Transfer filter does not contain its recorded cargo")
    end
    picker.selected_index=index
    assert(UI.on_selection{player_index=player.index,element=picker},"Transfer selection was not handled")
  end
  select("ssk_transfer_from",from)
  select("ssk_transfer_to",to)
  select("ssk_transfer_material","copper-plate")
  assert(us.transfers.from==from and us.transfers.to==to and us.transfers.material=="copper-plate",
    "Transfer filters lost their selection")
  local query=Transfers.query(player.force,game.tick,us.period,us.transfers)
  assert(#query.rows==1 and query.items==50 and query.arrivals==1,"Transfer filters selected the wrong cargo")
  local filter=assert(find_named(panel,"ssk_transfer_from"))
  UI.refresh(player,true)
  assert(filter.valid,"Live Transfers refresh replaced the filter")
  select("ssk_transfer_material")
  log("TRANSFERS NATIVE PASS two delivered pods, exact counts and all filters")
end

local function verify_usage(element, root, result)
  local key=element.tags and element.tags.ssk_rate
  if key and key:match("#use$") then
    local node=find_action(root,"node",key)
    assert(node.tooltip[9]==" consumed", "Uses tooltip lost selected material")
    assert(element.caption==node.tooltip[6], "Uses label still shows consumer output")
    result[key]=element.caption
  end
  for _,child in pairs(element.children) do verify_usage(child,root,result) end
end

local function exercise_diagnostics(UI, player, root, us, case)
  local function click(element)
    assert(UI.on_click{player_index=player.index,element=assert(element)}, "Diagnostic click was not handled")
  end
  if case.watch then
    local watch=find_ui(root,"watch")
    assert(watch and not watch.enabled, "Watch should require an individual favourite")
    us.bal_favs={items={[case.focus]=true},groups={}}
    UI.refresh(player)
    watch=find_ui(root,"watch")
    assert(watch.enabled and watch.style.name=="tool_button", "Watch must use an enabled vanilla icon control")
    click(watch)
    local dialog=assert(player.gui.screen.ssk_watch,"Watch dialog did not open")
    UI.refresh(player,true)
    assert(dialog.valid,"Live update closed the watch dialog")
    local function set_minimum(element)
      if element.name=="ssk_watch_made" then element.text="99999"; return true end
      for _,child in pairs(element.children) do if set_minimum(child) then return true end end
    end
    assert(set_minimum(dialog),"Missing minimum output field")
    after_capture=function()
      click(find_ui(dialog,"watch_apply"))
      assert(not dialog.valid and root.valid,"Applying a watch must close only the dialog")
      assert(find_ui(root,"watch").toggled,"Watch was not saved")
      log("BALANCE DIAGNOSTICS PASS watch configuration")
    end
  elseif case.sort then
    local sort=assert(find_ui(root,"bal_sort"),"Missing Balance sort selector")
    sort.selected_index=case.sort
    assert(UI.on_selection{player_index=player.index,element=sort}, "Urgency sort selection was not handled")
    assert(us.bal_sort==({[3]="deficit",[4]="empty"})[case.sort],"Urgency sort did not save")
    local list=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root
    UI.refresh(player,true)
    assert(list.valid and find_ui(root,"bal_sort").selected_index==case.sort,"Urgency sort changed on live refresh")
    log("BALANCE DIAGNOSTICS PASS sort "..us.bal_sort)
  elseif case.watch_warning then
    local function warning_caption(caption)
      if caption=="[img=utility/warning_icon] " then return true end
      if type(caption)=="table" then
        for _,part in ipairs(caption) do if warning_caption(part) then return true end end
      end
    end
    local function has_warning(element)
      if element.type=="label" and warning_caption(element.caption) then return true end
      for _,child in pairs(element.children) do if has_warning(child) then return true end end
    end
    assert(has_warning(root),"A sustained watch breach must show on the favourite row")
    log("BALANCE DIAGNOSTICS PASS sustained warning")
  elseif case.machine then
    local machine_action="ssk_machine_status"
    click(find_ui(root,"machine_status"))
    local status=assert(player.gui.screen.ssk_machine_status,"Machine status did not open")
    local target=assert(find_ui(status,"preview",machine_action),"No action for the sampled fixture machine")
    assert(target.enabled and target.parent.ssk_machine_count.caption=="1" and target.tags.recipe=="iron-gear-wheel",
      "Wrong stalled recipe or count")
    local age=assert(find_ui(status,"iron-gear-wheel","ssk_machine_age"),"Sample age is missing")
    assert(age.tags.sample_tick<=game.tick and age.tags.sample_tick>=game.tick-600,"Fixture sample is stale")
    if case.machine=="preview" then
      click(target)
      local preview=assert(player.gui.screen.ssk_machine_preview,"Map preview did not open")
      local slider=assert(find_ui(preview,"zoom",machine_action),"Map preview is missing its zoom slider")
      local function find_camera(element)
        if element.name=="ssk_machine_camera" then return element end
        for _,child in pairs(element.children) do local result=find_camera(child); if result then return result end end
      end
      local camera=assert(find_camera(preview),"Map preview is missing its camera")
      assert(camera.surface_index==diagnostic_machine.surface.index,"Preview has the wrong surface")
      local zoom=camera.zoom
      slider.slider_value=slider.get_slider_minimum()
      if slider.slider_value==zoom then slider.slider_value=slider.get_slider_maximum() end
      assert(UI.on_value_changed{player_index=player.index,element=slider},"Preview zoom change was not handled")
      assert(camera.zoom~=zoom,"Zoom slider did not change the map preview")
      assert(UI.on_closed{player_index=player.index,element=root},"Preview Esc was not handled")
      assert(not preview.valid and status.valid and root.valid,"Esc did not return to machine status")
      click(target)
      preview=assert(player.gui.screen.ssk_machine_preview)
      after_capture=function()
        click(find_ui(preview,"jump",machine_action))
        assert(not preview.valid and not status.valid and not root.valid,"Map jump must close the Production Flow windows")
        assert(player.centered_on==diagnostic_machine and player.controller_type==defines.controllers.remote,
          "Map jump did not center remote view on the fixture machine")
        log("BALANCE DIAGNOSTICS PASS preview zoom, Esc and map jump")
      end
    else
      log("BALANCE DIAGNOSTICS PASS sampled stalled recipe")
    end
  end
end

function T.tick(UI, Sampler)
  start = start or game.tick
  local elapsed = game.tick - start
  if mode == "history" then
    if elapsed == 0 then
      game.speed = 64
      for _, p in pairs(game.players) do UI.close(p) end
      log("SANKEY SAVE START tick="..game.tick)
    end
    if elapsed % 3600 == 0 then log("SANKEY SAVE progress="..elapsed.."/36060") end
    if elapsed == 36060 then
      local report = {tick=game.tick, elapsed_ticks=elapsed, surfaces={}, mods=script.active_mods}
      for _, s in pairs(game.surfaces) do
        if s.name ~= "ssk-canvas" then
          local rates, secs = Sampler.rates(s.index, 600)
          assert(secs == 600, s.name.." history is "..secs.." seconds")
          local m = Model.build(s.index, 600)
          local n = 0; for _ in pairs(rates.recipes) do n=n+1 end
          report.surfaces[#report.surfaces+1]={name=s.name, seconds=secs, recipes=n, edges=#m.edges}
        end
      end
      helpers.write_file("save-test/history.json", helpers.table_to_json(report), false)
      game.auto_save("sankey-warmed")
      log("SANKEY SAVE HISTORY OK")
    end
    return
  end
  if after_capture and not capture then
    local callback=after_capture
    after_capture=nil
    callback()
  end
  if elapsed == 0 then
    if mode=="audit" then audit_stock(Sampler) end
    if mode=="diagnostics" then
      local surface=game.create_surface("ssk-diagnostics-fixture",{width=96,height=96,seed=471})
      surface.request_to_generate_chunks({0,0},1)
      surface.force_generate_chunk_requests()
      surface.set_tiles{{name="stone-path",position={0,0}}}
      game.forces.player.chart(surface,{{-32,-32},{32,32}})
      diagnostic_machine=assert(surface.create_entity{name="assembling-machine-2",position={0,0},force="player",raise_built=true})
      diagnostic_machine.set_recipe("iron-gear-wheel")
    end
    if mode=="transfer-view" then transfer_fixture=start_transfer_fixture() end
    game.speed = mode=="transfer-view" and 8 or 1
    local _, seconds = Sampler.rates(game.surfaces.nauvis.index, 600)
    if mode~="warmup" then assert(seconds == 600, "Ten-minute history did not survive save/reload")
    else assert(seconds<600,"Warm-up case must use a fresh installation's history") end
    Sampler.on_stock(game.tick)
    log("SANKEY SAVE RELOAD HISTORY OK")
  end
  if mode=="transfer-view" then
    if elapsed==520 then send_fixture_cargo(transfer_fixture,"steel-plate",41,40) end
    if elapsed<1800 then return end
    game.speed=1
  end
  if not Sampler.stock_known(game.surfaces.nauvis.index) then return end
  local next_case=not capture and cases[step+1]
  if mode=="history-view" and not stock_fixture and next_case and next_case.focus=="item/iron-plate" then
    -- The warmed fixture supplies real rates. Two controlled historical scan
    -- results let this native view exercise interpolation without waiting for scans.
    local scope=game.surfaces.nauvis.index
    local latest=storage.stock[#storage.stock]
    if game.tick<latest.tick+120 then return end -- Let the rate sampler close the bucket containing the latest scan.
    local count=(latest.s[scope] or {})["item/iron-plate"] or 0
    table.insert(storage.stock,1,{tick=game.tick-530*60,s={[scope]={["item/iron-plate"]=count+1600}}})
    table.insert(storage.stock,2,{tick=game.tick-210*60,s={[scope]={["item/iron-plate"]=count+750}}})
    stock_fixture=true
    log("BALANCE HISTORY fixture uses real production rates and two controlled older stock samples")
  end
  if mode=="audit" and not Sampler.stock_known(audit_fixture.surface) then return end
  if selection and selection.click_tick and game.tick>=selection.click_tick then
    -- Wait until the before screenshot and native scroll layout have rendered.
    -- Simulate rates changing after the displayed list was built, then exercise
    -- the actual row handler without any subsequent scroll correction.
    local original_rows=Balance.rows
    Balance.rows=function(...)
      local rows,seconds=original_rows(...)
      local changed={}
      for i=#rows,2,-1 do rows[i].status="ok"; changed[#changed+1]=rows[i] end
      return changed,seconds
    end
    assert(UI.on_click{element=selection.target,player_index=selection.player.index})
    Balance.rows=original_rows
    assert(selection.list.valid and selection.items.valid and selection.target.valid,"Row selection rebuilt the scrolled list")
    local fx=SK.balance_state(storage.ui[selection.player.index])
    assert(fx.focus==selection.target.tags.key and fx.live==false,"Paused inspector did not select row")
    selection.click_tick=nil; selection.done=true
    capture=cases[step].name.."-after"
    log("BALANCE SELECTION PASS "..cases[step].name.." key="..fx.focus)
  end
  if elapsed % 60 ~= 0 then return end
  local player = game.connected_players[1]
  assert(player, "Graphical test has no connected player")
  if capture then
    assert(player.gui.screen.ssk_main, "Missing native GUI")
    if player.gui.screen.ssk_help then player.gui.screen.ssk_help.bring_to_front()
    elseif player.gui.screen.ssk_material_picker then player.gui.screen.ssk_material_picker.bring_to_front()
    elseif player.gui.screen.ssk_watch then player.gui.screen.ssk_watch.bring_to_front()
    elseif player.gui.screen.ssk_machine_preview then player.gui.screen.ssk_machine_preview.bring_to_front()
    elseif player.gui.screen.ssk_machine_status then player.gui.screen.ssk_machine_status.bring_to_front()
    else player.gui.screen.ssk_main.bring_to_front() end
    if mode=="scroll" and cases[step].bottom then
      -- Live sampling can reorder rows between setup and capture. Exercise the
      -- current list after that refresh, immediately before engine rendering.
      local root=player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root
      local sections=root.ssk_bal_list.ssk_bal_items.children
      local table=sections[#sections].ssk_bal_table
      local rows=table.children
      root.ssk_bal_list.ssk_bal_items.scroll_to_element(rows[#rows-table.column_count+1],"in-view")
    end
    local usage={}
    verify_usage(player.gui.screen.ssk_main,player.gui.screen.ssk_main,usage)
    if next(usage) then usage_labels[capture]=usage end
    if mode=="audit" then finish_audit(Sampler) end
    local node = find_node(player.gui.screen.ssk_main)
    if node then
      assert(node.tooltip ~= nil, "Node has no tooltip")
      assert(UI.on_hover({element=node, player_index=player.index}, true))
      assert(UI.on_hover({element=node, player_index=player.index}, false))
    end
    -- The hidden native window can inherit the desktop cursor position. Clear
    -- tooltip properties only after assertions so that incidental hover popups
    -- do not cover the review captures. The next case reconstructs the GUI.
    local function suppress_tooltips(el)
      el.tooltip=nil
      for _,child in pairs(el.children) do suppress_tooltips(child) end
    end
    suppress_tooltips(player.gui.screen.ssk_main)
    game.take_screenshot{player=player, path="save-test/"..capture..".png",
      resolution={1920,1080}, show_gui=true, force_render=true}
    log("SANKEY SAVE captured="..capture)
    captures[#captures+1] = capture
    capture = nil
    if selection then
      if selection.done then selection=nil
      else selection.click_tick=game.tick+1 end
    end
    return
  end
  if mode=="diagnostics" and cases[step+1] and cases[step+1].watch_warning and elapsed<900 then return end
  step = step+1
  local c = cases[step]
  if not c then
    if step == #cases+1 then
      Diag.export(player, "save-test")
      helpers.write_file("save-test/gui.json", helpers.table_to_json({captures=captures, skipped=skipped, products=products, usage_labels=usage_labels, display_scale=player.display_scale, display_resolution=player.display_resolution, upgrade=storage.ssk_save_test_upgrade}), false)
      log("SANKEY SAVE GUI OK")
    end
    return
  end
  if not game.surfaces[c.surface] then
    log("SANKEY SAVE skipped absent="..c.surface)
    skipped[#skipped+1]=c.name
    return
  end
  UI.open(player)
  assert(not commands.commands["sankey-export"] and not commands.commands["sankey-probe"] and not commands.commands["sankey-test"],"Release has development commands")
  assert(not settings.global["ssk-auto-export-minutes"] and not player.mod_settings["ssk-debug-tabs"],"Release has development settings")
  local tabs=player.gui.screen.ssk_main.ssk_inner.ssk_tabs
  assert(#tabs.tabs==4 and tabs.content_transfers,"Release needs Balance, Focus, Full Sankey and Transfers")
  local us = storage.ui[player.index]
  assert(us.period == 600, "10m is not the initial default")
  us.surface, us.tab_id, us.view = c.surface, c.tab, c.view or "overview"
  us.live = false
  us.renderer = c.renderer or "poly"
  if mode=="scroll" or mode=="selection" or mode=="picker" or mode=="ux" or mode=="warmup" then
    us.bal_filter="all"; us.bal_details=c.details or false; us.bal_sort=c.groups and "groups" or "priority"; us.bal_group=nil
    us.bal_favs=c.favs or nil
  end
  if mode=="diagnostics" then
    us.bal_filter="all"
    if c.watch then us.bal_favs,us.bal_watches=nil,nil end
  end
  if mode=="history-view" then
    us.bal_filter,us.bal_group="all",nil
    us.bal_mode="flow"
    us.bal_favs={items={[c.focus]=true},groups={}}
  end
  if (mode=="full" or mode=="names") then
    us.preset=c.preset or "all"; us.sel=nil; us.layout_snapshot=nil; us.auto_rank=nil
    us.show_labels=true; us.heights=c.heights or "sqrt"; us.color_mode="destination"
    us.layout="clean"; us.tier_mode="depth"; us.tier_lo=nil; us.tier_hi=nil
  end
  if c.tab == "balance" and c.focus then
    local fx=SK.balance_state(us); fx.focus=c.focus; fx.input_depth=c.depth; fx.show_labels=true; fx.live=false
    fx.heights=c.heights or "sqrt"; fx.pinned=nil; fx.color_mode="destination"
    local rates, seconds=Sampler.rates(game.surfaces[c.surface].index,600)
    local producers={}
    for _,rn in ipairs(storage.graph.nodes[c.focus].producers) do
      if rates.recipes[rn] and rates.recipes[rn].cps>0 then producers[rn]=rates.recipes[rn].cps end
    end
    products[c.name]={surface=c.surface,focus=c.focus,seconds=seconds,producers=producers}
    if c.name=="balance-condensation" then assert(producers["steam-condensation"], "No measured steam condensation") end
  elseif c.tab == "focus" then
    local fx=SK.focus_state(us); if c.focus then fx.focus=c.focus end; fx.live=false
    if mode=="focus" then fx.renderer=c.renderer or "poly"; fx.show_labels=true; fx.focus_steps=3 end
    if (mode=="full" or mode=="names") then fx.show_labels=true; fx.focus_steps=2; fx.layout_snapshot=nil; fx.auto_rank=nil end
  end
  UI.open(player)
  if c.tab~="transfers" then assert(us.sidx==game.surfaces[c.surface].index,"Wrong rendered surface") end
  if mode=="transfer-view" then
    exercise_transfers(UI,player,player.gui.screen.ssk_main,us)
    capture=c.name
    return
  end
  if c.advanced then
    UI.on_click{player_index=player.index,element=find_action(player.gui.screen.ssk_main,"chart_settings")}
    assert(us.settings_open and player.gui.screen.ssk_main.ssk_inner.ssk_tabs["content_"..c.tab].ssk_chart.ssk_settings,"Chart settings did not open")
  end
  if mode=="focus" then
    local root=player.gui.screen.ssk_main
    if c.pick then
      local function matching(el, predicate)
        if predicate(el) then return el end
        for _,child in ipairs(el.children) do local hit=matching(child,predicate);if hit then return hit end end
      end
      UI.on_click{element=assert(matching(root,function(el) return el.tags.ssk_picker=="open" end)),player_index=player.index}
      local dialog=assert(player.gui.screen.ssk_material_picker)
      dialog.ssk_title.ssk_query.text=c.pick:match("/(.+)$"):gsub("%-"," ")
      UI.on_text_changed{element=dialog.ssk_title.ssk_query,player_index=player.index}
      local slot=assert(matching(dialog,function(el) return el.tags.ssk_picker=="pick" and el.tags.key==c.pick end))
      assert(UI.on_click{element=slot,player_index=player.index})
    elseif c.back then
      assert(UI.on_click{element=find_action(root,"f_back"),player_index=player.index})
    end
    local fx=SK.focus_state(us)
    local L=View.build(player,fx,us.canvas_w,us.canvas_h)
    if c.empty then
      assert(fx.focus==c.pick and not next(L.nodes) and #L.links==0,"Unrecorded Focus leaked factory chart")
      assert(not find_node(root),"Empty Focus retained old GUI nodes")
      for _,obj in pairs(storage.canvas[player.index].objs) do assert(not obj.valid,"Empty Focus retained polygons") end
    else
      assert(fx.focus=="fluid/petroleum-gas" and L.nodes[fx.focus] and #L.links>0,"Active Focus/back did not restore oil flow")
    end
    log("FOCUS REGRESSION PASS "..c.name.." selection="..fx.focus.." flows="..#L.links)
  end
  if c.name=="full-platform-copper" or c.name=="full-vulcanus-copper" then
    local preset_picker=find_action(player.gui.screen.ssk_main,"preset")
    assert(us.preset_ids[preset_picker.selected_index]==us.preset,"Preset picker does not identify the displayed copper chain")
    local L=View.build(player,us,us.canvas_w,us.canvas_h)
    assert(L.nodes["item/copper-plate"] and L.nodes["fluid/molten-copper"],"plain copper chain lost its material names")
    for _,n in pairs(L.nodes) do assert(n.kind~="group","plain copper chain still has a category node") end
  end
  assert(us.surface_names[find_scope(player.gui.screen.ssk_main).selected_index]==c.surface,"Surface picker does not identify rendered surface")
  if mode=="balance" or mode=="scroll" or mode=="ux" or mode=="warmup" or ((mode=="full" or mode=="names") and c.tab~="focus") then
    -- Balance and Focus keep Center in Chart settings; close them again before capture.
    local opened_settings=not find_action(player.gui.screen.ssk_main,"center_selection")
    if opened_settings then UI.on_click{player_index=player.index,element=find_action(player.gui.screen.ssk_main,"chart_settings")} end
    for _,action in ipairs({"center_selection","zoom_fit"}) do
      local button=find_action(player.gui.screen.ssk_main,action)
      assert(button, "Missing Balance action "..action)
      UI.on_click({player_index=player.index,element=button})
    end
    if c.pin then
      local target=find_action(player.gui.screen.ssk_main,"node",c.pin)
      assert(target,"Missing pin target")
      UI.on_click({player_index=player.index,element=target,shift=true})
      assert((c.tab=="balance" and SK.balance_state(us).pinned or us.sel)==c.pin,"Native pin action failed")
      local center=find_action(player.gui.screen.ssk_main,"center_selection")
      UI.on_click({player_index=player.index,element=center})
    end
    if opened_settings then UI.on_click{player_index=player.index,element=find_action(player.gui.screen.ssk_main,"chart_settings")} end
  end
  if mode=="scroll" then
    local left=player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table
    local root=left.ssk_bal_root
    assert(left.type=="flow" and root.ssk_bal_list.ssk_bal_items.type=="scroll-pane")
    assert(root.ssk_bal_summary and not root.ssk_bal_context and root.ssk_bal_controls.ssk_bal_refresh and not root.ssk_bal_footer)
    local heading=root.ssk_bal_list.ssk_bal_header
    assert(not heading.ssk_bal_column_groups,"Redundant upper column headings remain")
    local columns=heading.ssk_bal_columns
    for _,section in ipairs(root.ssk_bal_list.ssk_bal_items.children) do
      local rows=section.ssk_bal_table
      if rows then
        assert(section.style.right_padding>=8,"Last column is too close to the scrollbar")
        assert(rows.column_count==columns.column_count,"Header and rows have different columns")
        for i,column in ipairs(columns.children) do
          assert(column.style.minimal_width==rows.children[i].style.minimal_width,"Header and row column widths differ")
        end
      end
    end
    if c.bottom then
      local sections=root.ssk_bal_list.ssk_bal_items.children
      local table=sections[#sections].ssk_bal_table
      local rows=table.children
      root.ssk_bal_list.ssk_bal_items.scroll_to_element(rows[#rows-table.column_count+1],"in-view")
    end
  end
  -- Native GUI identity check: a live refresh must retain the controls used by
  -- open selectors, and a hovered node must survive until the pointer leaves.
  local root=player.gui.screen.ssk_main
  local function find_named(el,name)
    if el.name==name then return el end
    for _,child in pairs(el.children) do local x=find_named(child,name); if x then return x end end
  end
  local bar=find_named(root,"ssk_bar")
  local control=bar.children[1]
  local fx=c.tab=="balance" and SK.balance_state(us) or c.tab=="focus" and SK.focus_state(us) or us
  local was_live=fx.live; fx.live=true
  UI.refresh(player,true)
  assert(control.valid and bar.children[1]==control,"Live refresh destroyed selector controls")
  local node=find_node(root)
  if node then
    UI.on_hover({element=node,player_index=player.index},true)
    UI.refresh(player,true)
    assert(node.valid,"Live refresh destroyed hovered selection")
    UI.on_hover({element=node,player_index=player.index},false)
  end
  fx.live=was_live

  if mode=="picker" and c.tab~="sankey" then
    fx.settings_open = nil
    UI.refresh(player,false,false,true)
    local bar=find_named(root,"ssk_bar")
    local chart=bar.parent
    local toolbar_h,chart_h=bar.style.minimal_height,chart.ssk_sp.style.minimal_height
    assert(not chart.ssk_settings,"Chart settings should start closed")
    local list_before=find_named(root,"ssk_bal_root")
    if list_before then
      assert(not list_before.ssk_bal_footer and list_before.ssk_bal_controls.ssk_bal_refresh.tags.ssk_ui=="bal_update", "Refresh belongs in the Balance header with no footer")
    end
    UI.on_click{player_index=player.index,element=find_action(root,"chart_settings")}
    assert(chart.ssk_settings and find_action(chart.ssk_settings,"f_heights"),"Chart settings did not open")
    assert(bar.style.minimal_height==toolbar_h and chart.ssk_sp.style.minimal_height==chart_h,"Chart settings moved the chart")
    if list_before then assert(list_before.valid,"Chart settings rebuilt Balance list") end
    UI.on_closed{player_index=player.index,element=root}
    assert(root.valid and not chart.ssk_settings and player.opened==root,"Esc must close chart settings before the window")
    if c.options then
      UI.on_click{player_index=player.index,element=find_action(root,"chart_settings")}
      assert(chart.ssk_settings,"Chart settings did not reopen")
    end
    local function picker_action(el,action)
      if el.tags and el.tags.ssk_picker==action then return el end
      for _,child in pairs(el.children) do local hit=picker_action(child,action);if hit then return hit end end
    end
    if c.tab=="balance" then
      local slot=assert(find_named(bar,"ssk_material_slot"))
      assert(slot.locked and not picker_action(bar,"open"),"Balance toolbar must be read-only")
      assert(UI.on_click{player_index=player.index,element=assert(material_row(list_before,c.pick))})
      assert(fx.focus==c.pick and list_before.valid,"Selecting from the Balance list must keep its scroller")
      if c.bottom then
        local items=list_before.ssk_bal_list.ssk_bal_items
        local sections=items.children
        local t=sections[#sections].ssk_bal_table
        items.scroll_to_element(t.children[#t.children-t.column_count+1],"in-view")
      end
    else
      fx.focus_hist,fx.focus_forward={},{}
      SK.select_focus(fx,"item/copper-plate")
      UI.refresh(player,false,false,true)
      UI.on_click{player_index=player.index,element=picker_action(root,"open")}
      local dialog=assert(player.gui.screen.ssk_material_picker)
      local grid=find_named(dialog,"ssk_results")
      assert(grid.type=="table" and grid.tags.total>100,"Incomplete material icon grid")
      local categories=dialog.ssk_material_inner.ssk_group_scroll.ssk_groups
      for _,category in pairs(categories.children) do
        assert(category.tags.group~="other" and category.tags.group~="signals", "Excluded selector category remains visible")
      end
      for _,query in ipairs({"parameter-", "blueprint", "deconstruction planner"}) do
        dialog.ssk_title.ssk_query.text=query
        UI.on_text_changed{player_index=player.index,element=dialog.ssk_title.ssk_query}
        for _,key in ipairs(grid.tags.keys) do
          local kind,name=key:match("^(%a+)/(.+)$")
          local proto=prototypes[kind][name]
          assert(not proto.parameter and proto.group.name~="other" and proto.group.name~="signals", "Excluded selector entry leaked into search")
        end
      end
      UI.refresh(player,true)
      assert(dialog.valid,"Live refresh destroyed open material picker")
      if c.group_material then
        dialog.ssk_title.ssk_query.text=""
        UI.on_text_changed{player_index=player.index,element=dialog.ssk_title.ssk_query}
        local kind,name=c.group_material:match("^(%a+)/(.+)$")
        local wanted=kind=="fluid" and "fluids" or prototypes[kind][name].group.name
        local function group_button(el)
          if el.tags.ssk_picker=="group" and el.tags.group==wanted then return el end
          for _,child in pairs(el.children) do local hit=group_button(child);if hit then return hit end end
        end
        UI.on_click{player_index=player.index,element=assert(group_button(dialog))}
      end
      dialog.ssk_title.ssk_query.text=c.query or c.pick:match("/(.+)$"):gsub("%-"," ")
      UI.on_text_changed{player_index=player.index,element=dialog.ssk_title.ssk_query}
      if c.expect_scroll then
        local scroll=dialog.ssk_material_inner.ssk_slot_frame.ssk_slot_scroll
        assert(math.ceil(#grid.children/grid.column_count)*40 > scroll.style.minimal_height,
          "Scrollbar reference case must contain more rows than fit")
      end
      if c.pick then
        local function material_button(el)
          if el.tags.ssk_picker=="pick" and el.tags.key==c.pick then return el end
          for _,child in pairs(el.children) do local hit=material_button(child);if hit then return hit end end
        end
        UI.on_click{player_index=player.index,element=assert(material_button(dialog),"Material absent from icon grid")}
        assert(fx.focus==c.pick and not dialog.valid,"Native material choice failed")
        local previous=fx.focus_hist[#fx.focus_hist]
        UI.on_click{player_index=player.index,element=find_action(root,"f_back")}
        assert(fx.focus==previous and #fx.focus_forward==1,"Back lost forward material")
        UI.on_click{player_index=player.index,element=find_action(root,"f_forward")}
        assert(fx.focus==c.pick,"Forward did not restore material")
        UI.on_click{player_index=player.index,element=find_action(root,"f_trail")}
        assert(fx.focus==c.focus and #fx.focus_forward==2,"Trail did not restore parent path")
        UI.on_click{player_index=player.index,element=find_action(root,"f_forward")}
        if c.clear then
          local bins,focus=storage.bins,fx.focus
          UI.on_click{player_index=player.index,element=find_action(root,"f_clear_history")}
          assert(fx.focus==focus and #fx.focus_hist==0 and #fx.focus_forward==0 and storage.bins==bins,"Clear history changed material or production data")
          assert(not find_action(root,"f_back").enabled and not find_action(root,"f_forward").enabled,"Cleared history still navigates")
        end
      else
        assert(#grid.tags.keys>0,"Native search returned no materials")
      end
      if c.six_visits then
        fx.focus,fx.focus_hist,fx.focus_forward="item/iron-plate",{},{}
        for _,key in ipairs({"item/copper-plate","fluid/water","item/iron-gear-wheel","item/steel-plate","fluid/petroleum-gas","item/electronic-circuit"}) do
          SK.select_focus(fx,key)
        end
        UI.refresh(player,false,false,true)
        assert(#fx.focus_hist==6 and #find_action(root,"f_history").items==7,"Last visits must retain exactly six previous materials")
      end
      if c.stay_pick then
        SK.select_focus(fx,c.pick)
        UI.refresh(player,false,false,true)
        local empty=View.build(player,fx,us.canvas_w,us.canvas_h)
        assert(not next(empty.nodes) and not find_action(root,"node"),"Unrecorded wood restored unrelated factory flows")
      end
    end
    log("MATERIAL PICKER NATIVE PASS "..c.name)
  end

  if mode=="selection" then
    local list=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root
    local items=list.ssk_bal_list.ssk_bal_items
    local sections=items.children
    local table=sections[#sections].ssk_bal_table
    local rows=table.children
    local target=find_ui(rows[#rows-table.column_count+1],"focus_item")
    assert(target.tags.ssk_ui=="focus_item","Last row has no inspect button")
    items.scroll_to_element(target,"in-view")
    selection={player=player,list=list,items=items,target=target}
    capture=c.name.."-before"
    return
  end

  if mode=="ux" or mode=="warmup" then
    local help_button=find_ui(root,"help")
    assert(help_button.type=="sprite-button" and help_button.sprite=="utility/questionmark","Help must use built-in icon")
    assert(not find_ui(root,"export") and not find_action(root,"f_renderer"),"Normal menus expose development tools")
    if c.tab=="balance" then
      local chart=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_focus
      assert(not find_action(chart,"f_back") and not find_action(chart,"f_history"),"Balance chart must not show Focus history")
      local context=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root.ssk_bal_context
      assert(not context,"Balance list must not repeat the surface and period")
    end
    if c.recent then
      local period=find_ui(root,"period");period.selected_index=1
      UI.on_selection({player_index=player.index,element=period})
      assert(us.period==0,"Recent period action failed")
    end
    if c.update_list then
      local old=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root
      UI.on_click({player_index=player.index,element=find_ui(root,"bal_update")})
      assert(old.valid==false and SK.balance_state(us).focus==c.focus,"Update list interrupted inspected material")
    end
    if c.help_tab then
      UI.on_click({player_index=player.index,element=find_ui(root,"help")})
      assert(player.gui.screen.ssk_help,"Help action did not open")
      player.gui.screen.ssk_help.ssk_help_inner.ssk_help_tabs.selected_tab_index=c.help_tab
    end
    if mode=="warmup" then
      assert(root.ssk_window_bar.ssk_history.visible,"Fresh-install history indicator missing")
      assert(not settings.global["ssk-auto-export-minutes"],"Release must not declare development export settings")
    end
  end
  if mode=="diagnostics" then
    exercise_diagnostics(UI,player,player.gui.screen.ssk_main,us,c)
  elseif mode=="history-view" and not c.flow_only then
    exercise_history(UI,player,player.gui.screen.ssk_main,us,c)
  end
  capture = c.name
end
return T
