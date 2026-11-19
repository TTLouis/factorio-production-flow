-- A material/surface History handoff shared by Space Age and Space Exploration.
-- The caller's chart state remains in place while this temporary view is open.
local Loc=require("scripts.locale")
local Flows=require("scripts.transport_flows")
local Panels=require("scripts.se_transfer_panels")
local Entities=require("scripts.transport_history_entities")
local Sampler=require("scripts.sampler")
local H={}
-- Native tab strip plus its 8 px content padding (48 px, as in Balance and the
-- other Transfers views), so this frame ends on the same line as every tab.
local TAB_HEIGHT,TOOLBAR_HEIGHT=48,92
local LAYOUT=4
local function row(parent,name)
  local e=parent.add{type="flow",name=name,direction="horizontal"}
  e.style.vertical_align,e.style.horizontal_spacing="center",8
  return e
end
local function label(parent,caption,style)
  return parent.add{type="label",caption=caption,style=style}
end
local function spacer(parent) parent.add{type="empty-widget"}.style.horizontally_stretchable=true end
local function material_name(name) return (prototypes.item[name] or {}).localised_name or name end
local function clear_time(state)
  state.history.bucket,state.history.page,state.history.expanded=nil,nil,nil
  state.history._scroll_reset=true
  state.history.exchange,state.history.event_page=nil,nil
end

function H.open(player,us,tags)
  local surface=type(tags.surface_index)=="number" and game.surfaces[tags.surface_index]
  if not (surface and surface.valid and (tags.provider=="sa" or tags.provider=="se")
    and type(tags.material)=="string" and prototypes.item[tags.material]
    and (tags.direction=="imports" or tags.direction=="exports")) then return false end
  local available=Flows.history(player.force,surface,game.tick,us.period,{material=tags.material,direction=tags.direction,method=tags.method})
  if available.provider~=tags.provider then return false end
  local previous=us.transport_history
  local origin=previous and previous.origin or {tab=us.tab_id,surface=us.surface,
    surface_index=us.sidx or player.surface.index,period=us.period}
  us.transport_history={provider=tags.provider,origin=origin,surface_index=surface.index,
    history={material=tags.material,direction=tags.direction,method=tags.method,quality=tags.quality}}
  us.surface,us.sidx,us.tab_id=surface.name,surface.index,"transfers"
  return true
end

local function build(content,width,height)
  content.clear()
  local panel=content.add{type="flow",name="ssk_transport_history",direction="vertical",tags={width=width,height=height,layout=LAYOUT}}
  panel.style.width,panel.style.height,panel.style.vertical_spacing=width,height,0
  local tabs=panel.add{type="tabbed-pane",name="ssk_transport_history_tabs",style="tabbed_pane_with_no_side_padding",
    tags={transport_history_tabs=true}}
  tabs.style.width,tabs.style.top_margin=width,0
  local flow_tab=tabs.add{type="tab",caption=Loc("help-flow")}
  local flow=tabs.add{type="frame",name="transport_flow_exit",style="inside_deep_frame",direction="vertical"}
  flow.style.width,flow.style.height=width,height-TAB_HEIGHT;tabs.add_tab(flow_tab,flow)
  local history_tab=tabs.add{type="tab",caption=Loc("help-history")}
  local history=tabs.add{type="frame",name="transport_history_panel",style="inside_deep_frame",direction="vertical"}
  history.style.width,history.style.height,history.style.padding=width,height-TAB_HEIGHT,0
  local scroll_filters=height-TAB_HEIGHT-TOOLBAR_HEIGHT<64
  if scroll_filters then Panels.viewport(history,width,height-TAB_HEIGHT,"history") end
  local container=scroll_filters and history.viewport or history
  local toolbar=container.add{type="frame",name="toolbar",style="subheader_frame",direction="vertical",index=1}
  toolbar.style.height,toolbar.style.horizontally_stretchable=TOOLBAR_HEIGHT,true
  toolbar.style.left_padding,toolbar.style.right_padding,toolbar.style.top_padding,toolbar.style.bottom_padding=12,12,8,8
  local rows=toolbar.add{type="flow",name="rows",direction="vertical"};rows.style.vertical_spacing=8;rows.style.horizontally_stretchable=true
  local controls=row(rows,"controls");controls.style.height,controls.style.horizontally_stretchable=40,true
  for _,field in ipairs({"material","method","direction","quality"}) do
    local caption=field=="material" and Loc("se-material") or field=="method" and Loc("se-ui-transport")
      or field=="direction" and Loc("transfers-direction") or Loc("se-ui-quality")
    label(controls,caption)
    local pick=controls.add{type="drop-down",name="history_"..field,items={""},selected_index=1,
      tags={transport_history_filter=field}}
    pick.style.width=field=="material" and math.min(230,math.floor(width*.18)) or field=="direction" and 160 or field=="method" and 148 or 120
  end
  spacer(controls)
  label(controls,"","grey_label").name="coverage"
  controls.add{type="sprite-button",style="tool_button",sprite="utility/backward_arrow",
    tooltip=Loc("transport-history-return"),tags={ssk_ui="transport_history_return"}}
  local context=row(rows,"context");context.style.height,context.style.horizontally_stretchable=28,true
  if not scroll_filters then Panels.viewport(history,width,height-TAB_HEIGHT-TOOLBAR_HEIGHT,"history") end
  tabs.add_tab(history_tab,history);tabs.selected_tab_index=2
  return panel
end

local function choices(control,state,field,values,captions)
  state["_"..field.."_choices"]=values
  control.items=captions;local selected=1
  for i,value in ipairs(values) do if value==state.history[field] then selected=i end end
  control.selected_index=selected
end

function H.render(content,player,us,width,height)
  local state=us.transport_history
  local surface=state and game.surfaces[us.sidx]
  if not (state and surface and surface.valid) then return end
  state.history=state.history or {}
  if state.surface_index~=surface.index or state.period~=us.period then
    clear_time(state);state.surface_index,state.period=surface.index,us.period
  end
  local data=Flows.history(player.force,surface,game.tick,us.period,{
    material=state.history.material,quality=state.history.quality,method=state.history.method,
    direction=state.history.direction,route=state.history.route,timing="either"})
  -- Reconfiguration must not relabel another provider's ledger as this handoff.
  if data.provider and data.provider~=state.provider then data.records,data.materials,data.qualities={},{},{} end
  local panel=content.ssk_transport_history
  if not panel or panel.tags.width~=width or panel.tags.height~=height or panel.tags.layout~=LAYOUT then panel=build(content,width,height) end
  panel.ssk_transport_history_tabs.selected_tab_index=2
  local frame=panel.ssk_transport_history_tabs.transport_history_panel
  local toolbar=frame.toolbar or frame.viewport.toolbar
  local controls=toolbar.rows.controls
  local names,captions={false},{Loc("se-all-materials")};local present={}
  for _,name in ipairs(data.materials or {}) do
    names[#names+1]=name;captions[#captions+1]=material_name(name);present[name]=true
  end
  if state.history.material and not present[state.history.material] then
    names[#names+1]=state.history.material;captions[#captions+1]=material_name(state.history.material)
  end
  choices(controls.history_material,state,"material",names,captions)
  if state.provider=="sa" then
    choices(controls.history_method,state,"method",{false,"cargo-pod"},{Loc("se-ui-all-transport"),Loc("transport-history-cargo-pods")})
  else
    choices(controls.history_method,state,"method",{false,"rocket","cannon"},{Loc("se-ui-all-transport"),Loc("se-cargo-rockets"),Loc("se-ui-cannons")})
  end
  choices(controls.history_direction,state,"direction",{false,"imports","exports"},
    {Loc("transport-history-all-directions"),Loc("se-imports"),Loc("se-exports")})
  local qualities,quality_captions={false},{Loc("se-ui-all-qualities")};local seen={}
  for _,quality in ipairs(data.qualities or {}) do qualities[#qualities+1]=quality;seen[quality]=true end
  if state.history.quality and not seen[state.history.quality] then qualities[#qualities+1]=state.history.quality end
  for i=2,#qualities do
    local quality=qualities[i];quality_captions[i]=(prototypes.quality and prototypes.quality[quality] or {}).localised_name or quality
  end
  choices(controls.history_quality,state,"quality",qualities,quality_captions)
  local coverage=data.coverage or {}
  local seconds=coverage[state.history.method=="cannon" and "cannon" or "rocket"] or coverage.sent or data.seconds or 0
  controls.coverage.caption=Loc("ui-recorded",Sampler.duration(seconds),Sampler.duration(us.period))
  local body=frame.viewport.body
  local size=body.tags
  Entities.render(body,player,surface,us.period,state,size.width,size.height,data,nil,toolbar.rows.context)
end

function H.on_click(e,us,close_all)
  local state=us.transport_history
  if not state then return false end
  if (e.element.tags or {}).ssk_ui=="transport_history_return" then
    local origin=state.origin or {}
    us.tab_id=(origin.tab=="focus" or origin.tab=="sankey" or origin.tab=="balance") and origin.tab or "balance"
    us.surface,us.period=origin.surface,origin.period or us.period
    local player=game.get_player(e.player_index)
    if not origin.surface and player and player.surface.index~=origin.surface_index then
      local surface=game.surfaces[origin.surface_index]
      if surface and surface.valid then us.surface=surface.name end
    end
    us.transport_history=nil
    return "reopen"
  end
  return Entities.on_click(e,state) or Panels.on_click(e,state,close_all)
end

function H.on_text_changed(e,us)
  return us.transport_history and Entities.on_text_changed(e,us.transport_history) or false
end
function H.on_translated(e,us)
  return us.transport_history and Entities.on_translated(e,us.transport_history) or false
end

function H.on_selection(e,us)
  local state=us.transport_history
  if not state then return false end
  local tags=e.element.tags or {}
  if tags.transport_history_tabs then
    if e.element.selected_tab_index==1 then
      us.transport_history=nil
      us.transfers=us.transfers or {};us.transfers.view="flow"
      us.se_logistics=us.se_logistics or {};us.se_logistics.view="flow"
      return "reopen"
    end
    return true
  end
  local field=tags.transport_history_filter
  if field=="material" or field=="direction" or field=="method" or field=="quality" then
    state.history[field]=(state["_"..field.."_choices"] or {})[e.element.selected_index] or nil
    state.history.route=nil;clear_time(state)
    return true
  end
  return false
end
return H
