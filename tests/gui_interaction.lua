-- Injected into a private mod copy by gui_interaction.py. No OS input.
local T={}
local SK=require('scripts.sankey_ui')
local Sampler=require('scripts.sampler')
local Check=require('scripts.gui_interaction_checks')
local mode=require('scripts.gui_interaction_mode')
local broken=mode.broken
local RibbonCheck=mode.ribbons and require('scripts.gui_ribbon_checks')
local recipes={'iron-plate','copper-plate','iron-gear-wheel','copper-cable','electronic-circuit',
  'automation-science-pack','inserter','transport-belt','logistic-science-pack'}
local function rates()
  local result={recipes={},nodes={}}
  for _,name in ipairs(recipes) do
    local recipe=prototypes.recipe[name]
    if recipe then
      local cps=name=='iron-plate' and 8 or name=='copper-plate' and 6 or 1
      result.recipes[name]={cps=cps,normal_cps=cps}
      for _,side in ipairs({'ingredients','products'}) do
        for _,material in pairs(recipe[side]) do
          local key=material.type..'/'..material.name
          local node=result.nodes[key] or {prod=0,cons=0};result.nodes[key]=node
          local field=side=='ingredients' and 'cons' or 'prod'
          node[field]=node[field]+cps*(material.amount or ((material.amount_min+material.amount_max)/2))*(material.probability or 1)
        end
      end
    end
  end
  return result,600
end
Sampler.rates=rates
function T.init()
  if remote.interfaces.freeplay and remote.interfaces.freeplay.set_skip_intro then
    remote.call('freeplay','set_skip_intro',true)
  end
end
local function find(e,predicate)
  if predicate(e) then return e end
  for _,child in ipairs(e.children) do local found=find(child,predicate);if found then return found end end
end
local function open(UI,player,tab,renderer)
  UI.open(player)
  local us=storage.ui[player.index]
  us.tab_id=tab;us.surface='nauvis';us.live=false;us.period=600;us.bal_filter='all'
  us.view='detail';us.preset='all';us.sel=nil;us.layout_snapshot=nil;us.auto_rank=nil;us.show_labels=true
  us.chart_zoom=nil;us.chart_fit=nil;us.hidden={}
  us.layout='clean';us.tier_mode='depth';us.heights='sqrt';us.renderer=renderer;us.lines='curves'
  for _,fx in ipairs({SK.balance_state(us),SK.focus_state(us)}) do
    fx.focus='item/iron-plate';fx.live=false;fx.renderer=renderer;fx.input_depth=1;fx.show_labels=true
    fx.focus_steps=2;fx.pinned=nil;fx.layout_snapshot=nil
  end
  UI.open(player)
  return us
end
local cases={}
for _,renderer in ipairs({'poly','sprites'}) do
  for _,tab in ipairs({'balance','focus','sankey'}) do cases[#cases+1]={tab=tab,renderer=renderer,name=tab..'-'..renderer} end
end
if RibbonCheck then cases[#cases+1]={tab='sankey',renderer='poly',name='sankey-night-vision',night_vision=true} end
local function inspect(UI,p,c)
  local root=p.gui.screen.ssk_main
  local canvas=assert(find(root,function(e)return e.name=='ssk_canvas' end))
  local result=Check.inspect(canvas,p.display_scale)
  if broken then assert(#result.obstructions>0,'Historical chart obstruction did not reproduce')
  else Check.assert_clear(result) end
  local samples=result.rows[#result.rows]
  assert(samples,'Fixture needs top, middle and bottom rows in one column')
  if RibbonCheck and c.tab=='sankey' then result.ribbon_checks=RibbonCheck.inspect(canvas,p,c) end
  -- Snapshot before dispatch. Each callback check below reopens its own fresh
  -- case, and is explicitly not evidence of native mouse input.
  game.take_screenshot{player=p,path='gui-interaction/'..c.name..'.png',resolution={1920,1080},show_gui=true,force_render=true}
  result.name=c.name;result.tab=c.tab;result.renderer=c.renderer
  return result
end
local function handlers(UI,p,c,result)
  local samples=result.rows[#result.rows]
  result.handler_checks={}
  for _,which in ipairs({'top','middle','bottom'}) do
    local sample=samples[which]
    local us=open(UI,p,c.tab,c.renderer)
    local target=assert(find(p.gui.screen.ssk_main,function(e)return e.type=='sprite-button' and e.tags.ssk_sk=='node' and e.tags.key==sample.key end))
    assert(UI.on_click{element=target,player_index=p.index},'Row handler rejected '..which)
    local selected=c.tab=='sankey' and us.sel or (c.tab=='balance' and SK.balance_state(us) or SK.focus_state(us)).focus
    local expected=c.tab=='sankey' and sample.key or sample.key:gsub('#.*$','')
    assert(selected==expected,'Row handler selected wrong material')
    result.handler_checks[which]={key=sample.key,selected=selected,dispatch='direct handler; not mouse input'}
  end
end
local function chart_control(player, action, key)
  return assert(find(player.gui.screen.ssk_main,function(e)
    return e.tags.ssk_sk==action and (not key or e.tags.key==key)
  end),'Missing chart control '..action)
end
local function machine_sidebar(selection, section)
  local heading
  for _,el in ipairs(selection.ssk_selected_scroll.ssk_selected_rates.children) do
    local caption=el.caption
    local title=caption[1]
    if title=='production-flow.sankey-made-by' or title=='production-flow.sankey-used-by'
      or title=='production-flow.sankey-masked-recipes' then heading=title end
    if heading==section and title=='production-flow.sankey-recipe-rate'
      and helpers.table_to_json(caption):find('assembling-machine-2',1,true) then return true end
  end
end
local function zoom_test(UI,p,c,result)
  local key='item/iron-plate'
  local us=open(UI,p,c.tab,c.renderer)
  us.hidden['item/transport-belt']=true
  UI.open(p)
  local start=assert(storage.sk_render[p.index].display_zoom)
  assert(start==1,'Unexpected starting zoom')
  local overview=chart_control(p,'overview_jump',key)
  assert(UI.on_click{element=overview,player_index=p.index} and us.sel==key,'Overview must select a material')
  local bar=chart_control(p,'node',key)
  local tooltip=helpers.table_to_json(bar.tooltip)
  for _,entry in ipairs({'sankey-made-by','sankey-used-by','sankey-masked-recipes','transport-belt'}) do
    assert(tooltip:find(entry,1,true),'Missing recipe tooltip entry '..entry)
  end
  local selection=find(p.gui.screen.ssk_main,function(el)return el.name=='ssk_selected_material' end)
  if selection then
    assert(tooltip:find('assembling-machine-2',1,true),'Missing sampled producing entity icon')
    for _,action in ipairs({'hide','move_group','new_group','deselect'}) do
      assert(find(selection,function(el)return el.tags.ssk_sk==action end),'Missing sidebar action '..action)
    end
    result.sidebar_actions=true
    result.machine_tooltip=true
    if selection.ssk_selected_scroll then
      assert(machine_sidebar(selection,'production-flow.sankey-used-by'),'Missing sidebar consuming machine icon')
      local group=chart_control(p,'move_group')
      local pane=selection.ssk_selected_scroll
      local breakdown=assert(pane.ssk_selected_breakdown)
      local machine=assert(breakdown.ssk_machine_action)
      assert(breakdown.children[1].caption[1]=='production-flow.sankey-breakdown'
        and group.parent.get_index_in_parent()<breakdown.get_index_in_parent()
        and breakdown.get_index_in_parent()<pane.ssk_selected_rates.get_index_in_parent(),
        'Breakdown and Inspect machines must sit between grouping and the recipe rates')
      local editor=chart_control(p,'new_group').parent.ssk_newgroup
      local preset=chart_control(p,'preset')
      local mark=chart_control(p,'overview_jump',key)
      local refresh=assert(find(p.gui.screen.ssk_main,function(el)return el.tags.ssk_ui=='refresh' end))
      editor.text='Retain this draft'
      us.live=true
      UI.refresh(p,true)
      assert(UI.on_click{element=refresh,player_index=p.index})
      us.live=false
      assert(group==chart_control(p,'move_group') and editor.valid and editor.text=='Retain this draft')
      assert(preset==chart_control(p,'preset') and mark==chart_control(p,'overview_jump',key))
      assert(pane.ssk_selected_breakdown.ssk_machine_action==machine,'Graph refresh replaced Inspect machines')
      editor.text=''
      result.retained_graph_controls=true
      result.machine_sidebar=true
    end
  end
  assert(UI.on_click{element=chart_control(p,'zoom_in'),player_index=p.index})
  local enlarged=storage.sk_render[p.index].display_zoom
  assert(enlarged>start and us.sel==key,'Zoom must enlarge the chart and retain selection')
  if result.retained_graph_controls then assert(enlarged==1.1,'Zoom must move by ten percentage points') end
  assert(UI.on_click{element=chart_control(p,'zoom_fit'),player_index=p.index})
  local fitted=storage.sk_render[p.index].display_zoom
  local pane=assert(find(p.gui.screen.ssk_main,function(e)return e.name=='ssk_sp' end))
  assert(fitted<enlarged and us.sel==key and pane.horizontal_scroll_policy=='never','Fit must retain selection and remove horizontal scroll')
  if result.retained_graph_controls then
    assert(math.abs(fitted*10-math.floor(fitted*10+0.5))<1e-8,'Fit must snap to a ten-point step')
  end
  result.zoom_checks={start=start,enlarged=enlarged,fit=fitted,selected=key,masked_recipe_tooltip=true}
  if RibbonCheck then result.fit_join=RibbonCheck.fit_join(pane.ssk_canvas,p) end
end

local function inspect_selected_machine(UI,p)
  local us=storage.ui[p.index]
  local button=assert(find(p.gui.screen.ssk_main,function(el)
    return el.tags.ssk_ui=='machine_status'
  end))
  assert(UI.on_click{element=button,player_index=p.index})
  local status=assert(p.gui.screen.ssk_machine_status)
  assert(us.tab_id=='sankey' and status.tags.material==us.sel
    and status.tags.surface==us.sidx and status.tags.force==p.force_index,
    'Full Sankey must inspect its own selected material, surface and force')
  return status
end

local function navigation_test(UI,p,result)
  if not result.sidebar_actions then return end
  local us=storage.ui[p.index]
  local key,surface,period=us.sel,us.sidx,us.period
  for _,target in ipairs({'focus','balance'}) do
    if us.tab_id~='sankey' then us.tab_id='sankey';UI.open(p) end
    local element=assert(find(p.gui.screen.ssk_main,function(el)
      return el.tags.ssk_ui=='sankey_material_tab' and el.tags.target==target
    end))
    assert(UI.on_click{element=element,player_index=p.index})
    local state=target=='focus' and SK.focus_state(us) or SK.balance_state(us)
    assert(us.tab_id==target and state.focus==key and us.sidx==surface and us.period==period,
      'Material shortcut did not preserve the selection, surface and period')
  end
  result.material_shortcuts=true
  if result.machine_sidebar then
    us.tab_id='sankey';UI.open(p)
    local gear=chart_control(p,'overview_jump','item/iron-gear-wheel')
    assert(UI.on_click{element=gear,player_index=p.index})
    local selection=assert(find(p.gui.screen.ssk_main,function(el)return el.name=='ssk_selected_material' end))
    assert(machine_sidebar(selection,'production-flow.sankey-made-by'),'Missing sidebar producing machine icon')
    local pane=selection.ssk_selected_scroll
    pane.scroll_to_element(pane.ssk_selected_rates.children[2],'in-view')
    result.sidebar_made_by=true
  end
end
function T.tick(UI)
  local p=game.get_player(1)
  if not p or not p.connected then return end
  if RibbonCheck and p.controller_type==defines.controllers.cutscene then p.exit_cutscene();return end
  if not storage.gui_interaction then
    -- Native insertion/lifetime contracts used by retained Transfer targets.
    local root=p.gui.screen.add{type='flow',name='gui_api_smoke'}
    local hit=root.add{type='sprite',name='hit',sprite='item/iron-plate'}
    local other=root.add{type='sprite',name='other',sprite='item/copper-plate'}
    local reset=root.add{type='empty-widget',name='reset',index=hit.get_index_in_parent()+1,ignored_by_interaction=true}
    reset.style.width,reset.style.height=0,0
    assert(reset.get_index_in_parent()==2 and other.get_index_in_parent()==3,'Native indexed add misplaced reset')
    root.destroy()
    assert(not hit.valid and not other.valid and not reset.valid,'Native descendants must invalidate together')
    storage.gui_interaction={step=1,phase='open',next_tick=game.tick+10,results={}}
    p.force.research_all_technologies()
    if not broken and SK.scroll_pane then
      local surface=game.surfaces.nauvis
      local pos=assert(surface.find_non_colliding_position('assembling-machine-2',p.position,24,1))
      local assembler=assert(surface.create_entity{name='assembling-machine-2',position=pos,force=p.force})
      assembler.set_recipe('iron-gear-wheel')
      Sampler.add(assembler)
    end
  end
  local s=storage.gui_interaction
  if s.done or game.tick<s.next_tick then return end
  local c=cases[s.step]
  if not c then
    if not broken then
      local us=storage.ui[p.index]
      for _,field in ipairs({'fx','bal_fx'}) do
        us[field].focus='item/__removed_gui_test_material'
        us[field].focus_hist={'fluid/__removed_gui_test_fluid','item/iron-plate'}
      end
      for _,tab in ipairs({'focus','balance'}) do
        us.tab_id=tab;UI.open(p)
        local fx=tab=='focus' and SK.focus_state(us) or SK.balance_state(us)
        local kind,name
        if fx.focus then kind,name=fx.focus:match('^(%a+)/(.+)$') end
        assert((not fx.focus or (prototypes[kind] and prototypes[kind][name]))
          and #fx.focus_hist==1 and fx.focus_hist[1]=='item/iron-plate','Removed material survived native state sanitization')
      end
    end
    local evidence={cases=s.results,scale=p.display_scale,resolution=p.display_resolution,
      expected_obstruction=broken,engine_mouse_input=false,removed_material_check=not broken,fixture='vanilla synthetic rates'}
    helpers.write_file('gui-interaction/results.json',helpers.table_to_json(evidence),false,p.index)
    s.done=true;log('GUI INTERACTION NATIVE PASS '..helpers.table_to_json{cases=#s.results,scale=p.display_scale})
    return
  end
  if s.phase=='open' then
    if c.night_vision then RibbonCheck.equip(p) end
    open(UI,p,c.tab,c.renderer);s.phase='inspect';s.next_tick=game.tick+20
    return
  elseif s.phase=='inspect' then
    s.pending=inspect(UI,p,c);s.phase='handlers';s.next_tick=game.tick+5
    return
  elseif s.phase=='handlers' then
    handlers(UI,p,c,s.pending)
    if not broken and SK.scroll_pane and c.tab=='sankey' then
      zoom_test(UI,p,c,s.pending)
      s.phase='fit_capture';s.next_tick=game.tick+20
      return
    end
  elseif s.phase=='fit_capture' then
    game.take_screenshot{player=p,path='gui-interaction/'..c.name..'-fit.png',resolution={1920,1080},show_gui=true,force_render=true}
    s.pending.fit_capture=c.name..'-fit.png'
    s.phase='navigation';s.next_tick=game.tick+10
    return
  elseif s.phase=='navigation' then
    navigation_test(UI,p,s.pending)
    if s.pending.sidebar_made_by then
      s.phase='producer_capture';s.next_tick=game.tick+10
      return
    end
  elseif s.phase=='producer_capture' then
    s.pending.producer_capture=c.name..'-producer.png'
    game.take_screenshot{player=p,path='gui-interaction/'..s.pending.producer_capture,resolution={1920,1080},show_gui=true,force_render=true}
    s.phase='machine_open';s.next_tick=game.tick+10
    return
  elseif s.phase=='machine_open' then
    inspect_selected_machine(UI,p)
    s.phase='machine_capture';s.next_tick=game.tick+15
    return
  elseif s.phase=='machine_capture' then
    s.pending.machine_capture=c.name..'-machine-status.png'
    game.take_screenshot{player=p,path='gui-interaction/'..s.pending.machine_capture,resolution={1920,1080},show_gui=true,force_render=true}
    s.phase='machine_close';s.next_tick=game.tick+10
    return
  elseif s.phase=='machine_close' then
    local status=assert(p.gui.screen.ssk_machine_status)
    local close=assert(find(status,function(el)return el.tags.ssk_machine_status=='close' end))
    assert(UI.on_click{element=close,player_index=p.index} and not status.valid)
  end
  s.results[#s.results+1]=s.pending;s.pending=nil
  s.step=s.step+1;s.phase='open';s.next_tick=game.tick+10
end
return T
