local UI=TREQ("scripts.ui")
local Flows=TREQ("scripts.transport_flows")
local Transfers=TREQ("scripts.transfers")
local Rockets=TREQ("scripts.se_rockets")
local Data=TREQ("scripts.se_transfer_data")
local player,us=game.players[1],storage.ui[1]
local surface_valid=player.surface.valid;player.surface.valid=true
local saved={};for key,value in pairs(us) do saved[key]=value end
local old_history,old_query,old_sa,old_se=Flows.history,Flows.query,Transfers.available,Rockets.available
local provider,last_request
Transfers.available=function() return provider=="sa" end
Rockets.available=function() return provider=="se" end
Flows.query=function() return {materials={},events={}} end
local function find(e,predicate)
  if predicate(e) then return e end
  for _,child in ipairs(e.children or {}) do local result=find(child,predicate);if result then return result end end
end
local function window() return assert(player.gui.screen.ssk_main) end
local function panel() return assert(find(window(),function(e) return e.name=="ssk_transport_history" end)) end
local function click(element) return UI.on_click{element=element,player_index=player.index} end
local function select(element,index)
  element.selected_index=index
  return UI.on_selection{element=element,player_index=player.index}
end
Flows.history=function(force,surface,tick,seconds,filters)
  last_request={force=force,surface=surface,seconds=seconds,filters=filters}
  local method=provider=="sa" and "cargo-pod" or "rocket"
  local raw={}
  for _,direction in ipairs({"imports","exports"}) do
    raw[#raw+1]={key="fixture:"..direction,id=#raw+1,method=method,direction=direction,
      tick=tick-120,arrival_tick=tick-60,remote={surface=surface,name=surface.name},
      sent={{name="iron-plate",quality="normal",count=1000}},
      received={{name="iron-plate",quality="normal",count=750}}}
  end
  return {provider=provider,records=Data.filter(raw,filters),materials={"copper-plate","iron-plate"},qualities={"normal"},
    from_tick=tick-seconds*60,to_tick=tick,seconds=seconds,coverage={rocket=seconds,sent=seconds}}
end
for _,selected_provider in ipairs({"se","sa"}) do
  provider=selected_provider
  for _,origin in ipairs({"balance","focus","sankey"}) do
    us.tab_id,us.surface,us.period=origin,player.surface.name,600
    us.fx={view="focus",focus="item/iron-plate"};us.bal_fx={view="focus",neighborhood=true,focus="item/iron-plate"}
    us.bal_mode="flow"
    us.view,us.sel,us.hidden,us.collapsed="detail","item/iron-plate",{},{}
    us.transfers={view="flow"};us.se_logistics={view="flow",material="copper-plate"};us.transport_history=nil
    UI.open(player)
    local focus,balance,normal_se=us.fx,us.bal_fx,us.se_logistics
    assert(click{valid=true,tags={ssk_ui="transport_history",provider=provider,surface_index=player.surface.index,
      material="iron-plate",direction="exports",method=provider=="sa" and "cargo-pod" or "rocket"}})
    assert(us.tab_id=="transfers" and us.transport_history and us.transport_history.origin.tab==origin)
    assert(us.fx==focus and us.bal_fx==balance and us.se_logistics==normal_se,"Handoff replaced source chart/filter state")
    assert(window().ssk_window_bar.ssk_surface_picker.visible,"Generic SA/SE History must expose its surface scope")
    assert(panel().ssk_transport_history_tabs.selected_tab_index==2,"Handoff did not select History")
    assert(last_request.surface==player.surface and last_request.force==player.force
      and last_request.filters.material=="iron-plate" and last_request.filters.direction=="exports")
    assert(#us.transport_history.history._records==1)
    local axis=assert(find(panel(),function(e) return e.tags.transfer_axis end))
    assert(axis.type=="switch")
    axis.switch_state="right"
    assert(UI.on_switch{element=axis,player_index=player.index} and us.transport_history.history.axis=="events",
      "Shared SA/SE History ignored the axis toggle")
    assert(us.transport_history.history.material=="iron-plate" and us.transport_history.history.direction=="exports")
    axis=assert(find(panel(),function(e) return e.tags.transfer_axis end))
    axis.switch_state="left"
    assert(UI.on_switch{element=axis,player_index=player.index} and us.transport_history.history.axis=="time")
    if provider=="sa" then
      local cargo=find(panel(),function(e) return e.caption and LOC(e.caption):find("Cargo pods",1,true)~=nil end)
      assert(cargo,"SA History mislabeled cargo pods as cargo rockets")
    end
    local controls=panel().ssk_transport_history_tabs.transport_history_panel.toolbar.rows.controls
    UI.refresh(player,true)
    assert(panel().ssk_transport_history_tabs.transport_history_panel.toolbar.rows.controls==controls,"History refresh rebuilt native filter controls")
    assert(select(controls.history_direction,1) and us.transport_history.history.direction==nil)
    assert(#us.transport_history.history._records==2,"All-direction History filter was not applied")
    assert(select(controls.history_material,2) and us.transport_history.history.material=="copper-plate")
    assert(us.fx.focus=="item/iron-plate" and us.bal_fx.focus=="item/iron-plate","History material selection changed source material")
    -- Global period changes stay local to this temporary visit when returning.
    us.period=3600;UI.refresh(player)
    local back=assert(find(panel(),function(e) return e.tags.ssk_ui=="transport_history_return" end))
    assert(click(back) and not us.transport_history and us.tab_id==origin and us.period==600 and us.surface==player.surface.name)
    assert(us.fx==focus and us.bal_fx==balance and us.se_logistics==normal_se)
  end
  -- Flow exits the generic handoff into the provider's normal Transfers shell.
  us.tab_id="focus"
  assert(click{valid=true,tags={ssk_ui="transport_history",provider=provider,surface_index=player.surface.index,
    material="iron-plate",direction="imports"}})
  local tabs=panel().ssk_transport_history_tabs;tabs.selected_tab_index=1
  assert(UI.on_tab_changed{element=tabs,player_index=player.index})
  assert(us.tab_id=="transfers" and us.transport_history==nil and us.transfers.view=="flow" and us.se_logistics.view=="flow")
end
-- Reconfigured provider and removed-surface targets must not open another ledger.
us.tab_id="focus";us.transport_history=nil;UI.open(player)
assert(click{valid=true,tags={ssk_ui="transport_history",provider="se",surface_index=player.surface.index,material="iron-plate",direction="imports"}})
assert(us.tab_id=="focus" and not us.transport_history)
assert(click{valid=true,tags={ssk_ui="transport_history",provider="sa",surface_index=999999,material="iron-plate",direction="imports"}})
assert(us.tab_id=="focus" and not us.transport_history)
Flows.history,Flows.query,Transfers.available,Rockets.available=old_history,old_query,old_sa,old_se
player.surface.valid=surface_valid
for key in pairs(us) do us[key]=nil end
for key,value in pairs(saved) do us[key]=value end
UI.open(player)
print("TRANSPORT HISTORY UI PASS: SA/SE graph handoff, filtered scope/material/direction, native control stability, caller return and normal Flow exit")
