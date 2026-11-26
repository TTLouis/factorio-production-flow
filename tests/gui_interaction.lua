-- Injected into a private mod copy by gui_interaction.py. No OS input.
local T={}
local SK=require('scripts.sankey_ui')
local Sampler=require('scripts.sampler')
local History=require('scripts.history')
local Palette=require('shared.palette')
local Sprites=require('shared.sprites')
local Check=require('scripts.gui_interaction_checks')
local Budget=require('scripts.chart_budget')
local mode=require('scripts.gui_interaction_mode')
local broken=mode.broken
local RibbonCheck=mode.ribbons and require('scripts.gui_ribbon_checks')
local recipes={'iron-plate','copper-plate','iron-gear-wheel','copper-cable','electronic-circuit',
  'automation-science-pack','inserter','transport-belt','logistic-science-pack'}
local function rates(_, period)
  local result={recipes={},nodes={}}
  if storage.gui_interaction and storage.gui_interaction.stopped and period==Sampler.DEFAULT_PERIOD then
    return result,period
  end
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
  return result,period and period>0 and period or Sampler.DEFAULT_PERIOD
end
Sampler.rates=rates
local coverage=Sampler.coverage
function Sampler.coverage(sidx,period)
  if storage.gui_interaction and storage.gui_interaction.card_fixture then return period end
  return coverage(sidx,period)
end
local history_sources=Sampler.history_sources
function Sampler.history_sources(sidx, first, last, stats)
  if not stats or not storage.gui_interaction or not storage.gui_interaction.card_fixture then
    return history_sources(sidx,first,last,stats)
  end
  local sources={}
  local step=(last-first)/60
  for i=0,59 do
    local left, right=first+i*step, math.min(last,first+(i+1)*step)
    if left>=last then break end
    local stopped=storage.gui_interaction.stopped and left>=last-Sampler.DEFAULT_PERIOD*60
    local made, used=stopped and 0 or (6+(i%12)/2)*step/60, stopped and 0 or (6.5+(i%7)*.7)*step/60
    sources[#sources+1]={first=left,last=right,duration=right-left,known=true,
      bin={stat={[sidx]={['item/iron-plate']={i=made,o=used}}},rec={}}}
  end
  return sources
end
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
  else Check.assert_clear(result,c.tab~='sankey') end
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
local function card_body(selection)
  return selection.ssk_selected_scroll.ssk_rate_card_body
end
local function recipe_machine(selection, section)
  local recipes=card_body(selection)['ssk_rate_card_'..section]
  return recipes and find(recipes,function(el)
    return el.type=='label' and el.tags.ssk_machine_status=='card_preview' and el.tags.machine=='assembling-machine-2'
  end)
end
local function check_bar_contrast(player, key)
  local state=storage.sk_render[player.index]
  local bar_color=Palette.material(key)
  local function matches(color,index)
    local expected=Palette.tint(index)
    return math.abs(color.r-expected.r)<1e-4 and math.abs(color.g-expected.g)<1e-4
      and math.abs(color.b-expected.b)<1e-4
  end
  local bar=assert(state.node_visuals[key])
  assert(not bar.dimmed,'The highlighted material bar must stay bright')
  local bright=false
  for _,shape in ipairs(bar.shapes) do
    bright=bright or shape.color==bar_color and matches(shape.object.color,bar_color)
  end
  for _,sprite in ipairs(bar.sprites) do
    bright=bright or sprite.element.sprite==Sprites.bar(bar_color)
  end
  assert(bright,'The material bar must use the full palette colour')
  local checked=false
  for _,ribbon in ipairs(state.ribbons) do
    if ribbon.from=='item/iron-ore' and ribbon.to==key then
      local darker=Palette.muted(bar_color)
      assert(ribbon.ro and matches(ribbon.ro.color,darker)
        or ribbon.elem and tonumber(ribbon.elem.sprite:match('c(%d+)$'))==darker,
        'A same-colour flow must stay darker beside the highlighted bar')
      checked=true
    end
  end
  assert(checked,'Fixture must include a same-colour bar and ribbon')
end
local function zoom_test(UI,p,c,result)
  local key='item/iron-plate'
  local us=open(UI,p,c.tab,c.renderer)
  us.hidden['item/transport-belt']=true
  UI.open(p)
  local start=assert(storage.sk_render[p.index].display_zoom)
  assert(start==1,'Unexpected starting zoom')
  local hover={element=chart_control(p,'node',key),player_index=p.index}
  assert(SK.on_hover(hover,true))
  check_bar_contrast(p,key)
  assert(SK.on_hover(hover,false))
  local overview=chart_control(p,'overview_jump',key)
  assert(UI.on_click{element=overview,player_index=p.index} and us.sel==key,'Overview must select a material')
  check_bar_contrast(p,key)
  result.highlight_contrast=true
  local bar=chart_control(p,'node',key)
  local tooltip=helpers.table_to_json(bar.tooltip)
  for _,entry in ipairs({'recipe-details-made-by','recipe-details-used-by','sankey-rate-card-click'}) do
    assert(tooltip:find(entry,1,true),'Missing recipe tooltip entry '..entry)
  end
  assert(tooltip:find('assembling-machine-2',1,true),'Missing sampled consuming entity icon')
  local selection=assert(find(p.gui.screen.ssk_main,function(el)return el.name=='ssk_selected_material' end))
  local shortcuts=selection.ssk_selection_actions
  local more=shortcuts.ssk_selection_more
  local separator=assert(selection.ssk_selection_header_divider)
  assert(shortcuts.get_index_in_parent()<separator.get_index_in_parent()
    and separator.get_index_in_parent()<selection.ssk_selected_scroll.get_index_in_parent(),
    'Rate card must separate the shortcuts from the data')
  assert(not selection.ssk_selected_scroll.ssk_selection_menu and not more.toggled,'Actions must start closed')
  assert(UI.on_click{element=more,player_index=p.index})
  local menu=assert(selection.ssk_selected_scroll.ssk_selection_menu)
  assert(more.toggled and menu.visible,'More actions must open within the card')
  local divider=assert(menu.ssk_selection_group_divider)
  assert(menu.ssk_selection_layout.get_index_in_parent()<divider.get_index_in_parent()
    and divider.get_index_in_parent()<menu.ssk_selection_grouping.get_index_in_parent(),
    'Actions menu must separate chart layout and grouping')
  for _,action in ipairs({'hide','move_group','new_group','ungroup'}) do
    assert(find(menu,function(el)return el.tags.ssk_sk==action end),'Missing menu action '..action)
  end
  local machines=shortcuts.ssk_selection_machines
  local machine=assert(machines.ssk_machine_action)
  assert(machine.tags.key==key and recipe_machine(selection,'used_by'))
  local group=chart_control(p,'move_group')
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
  assert(machines.ssk_machine_action==machine,'Graph refresh replaced Inspect machines')
  editor.text=''
  assert(UI.on_closed{element=p.gui.screen.ssk_main,player_index=p.index} and not more.toggled and not menu.visible,
    'Esc should close the menu and keep the mod window open')
  result.retained_graph_controls=true
  result.sidebar_actions=true
  result.machine_sidebar=true
  result.machine_tooltip=true
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
    local recipe=assert(recipe_machine(selection,'made_by'),'Missing sidebar producing machine icon')
    selection.ssk_selected_scroll.scroll_to_element(recipe,'in-view')
    result.sidebar_made_by=true
  end
end
local function capture_viewport_modes(UI,p,s)
  local setting='ssk-live-sankey-overview'
  local preferences=settings.get_player_settings(p)
  if not preferences[setting] or s.viewport_stage=='done' then return false end
  if not s.viewport_stage then
    local us=open(UI,p,'sankey','sprites')
    us.chart_fit,us.chart_zoom=false,2.5
    UI.refresh(p,false,false,true,true)
    s.viewport_stage='off'
  elseif s.viewport_stage=='enable' or s.viewport_stage=='disable' then
    local enabled=s.viewport_stage=='enable'
    preferences[setting]={value=enabled}
    local handler=script.get_event_handler(defines.events.on_runtime_mod_setting_changed)
    handler{player_index=p.index,setting=setting,setting_type='runtime-per-user'}
    if enabled then
      local panel=p.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_sankey.ssk_chart
      local us=storage.ui[p.index]
      local v=assert(us.chart_viewport)
      assert(SK.pan_to(p,panel,us,v.max_x*.3,v.max_y*.3))
    end
    s.viewport_stage=enabled and 'on' or 'done'
  elseif s.viewport_stage=='select' then
    local key='item/electronic-circuit'
    local target=chart_control(p,'overview_jump',key)
    assert(UI.on_click{element=target,player_index=p.index})
    assert(storage.ui[p.index].sel==key)
    s.viewport_stage='selected'
  else
    local mode=s.viewport_stage
    local viewport=storage.ui[p.index].chart_viewport
    assert((viewport~=nil)==(mode~='off'),'Captured chart does not match the player preference')
    local filename='sankey-viewport-'..mode..'.png'
    game.take_screenshot{player=p,path='gui-interaction/'..filename,resolution={1920,1080},show_gui=true,force_render=true}
    s.viewport_modes=s.viewport_modes or {}
    s.viewport_modes[mode]=filename
    s.viewport_stage=mode=='off' and 'enable' or mode=='on' and 'select' or 'disable'
  end
  s.next_tick=game.tick+20
  return true
end

local function capture_ribbon_modes(UI,p,s)
  local setting='ssk-detailed-sankey-ribbons'
  local band_setting='ssk-sankey-overview-bands'
  local preferences=settings.get_player_settings(p)
  if not preferences[setting] or s.ribbon_stage=='done' then return false end
  local key='item/iron-plate'
  local function panel()
    return p.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_sankey.ssk_chart
  end
  local function overview_paths()
    return panel().ssk_body.ssk_sidebar.ssk_overview.ssk_overview_map.ssk_overview_paths
  end
  local function check(detailed)
    local result=Check.inspect(SK.scroll_pane(panel()).ssk_canvas,p.display_scale)
    Check.assert_clear(result,detailed)
    assert((result.ribbons>0)==detailed,'Ordinary ribbon hit regions disagree with the player setting')
    local bar=chart_control(p,'node',key)
    assert(bar.tooltip and bar.raise_hover_events,'Material hover must be available in both modes')
    local pieces=overview_paths().children
    local selected=storage.ui[p.index].sel==key
    local color=Palette.material(key)
    local suffix=string.format('-c%02d',selected and color or Palette.muted(color))
    local found=false
    for i=1,#pieces,2 do
      local band, reset=pieces[i], pieces[i+1]
      assert(band.type=='sprite' and band.ignored_by_interaction and reset.type=='empty-widget',
        'Overview bands must use one sprite and one offset reset')
      found=found or band.sprite:sub(-#suffix)==suffix
    end
    assert(found,'The iron plate overview bands must be visible with either hover setting')
  end
  if not s.ribbon_stage then
    assert(preferences[setting].value==false,'New profiles must start with compact ribbons')
    assert(settings.global[band_setting].value,'New maps must show overview bands')
    preferences['ssk-live-sankey-overview']={value=true}
    open(UI,p,'sankey','sprites')
    check(false)
    local dot=chart_control(p,'overview_jump',key)
    assert(UI.on_click{element=dot,player_index=p.index},'Overview jump did not select a material')
    check(false)
    s.ribbon_stage='compact'
  elseif s.ribbon_stage=='enable' or s.ribbon_stage=='disable' then
    local detailed=s.ribbon_stage=='enable'
    local old_pane=SK.scroll_pane(panel())
    preferences[setting]={value=detailed}
    script.get_event_handler(defines.events.on_runtime_mod_setting_changed){
      player_index=p.index,setting=setting,setting_type='runtime-per-user'}
    assert(old_pane==SK.scroll_pane(panel()) and storage.ui[p.index].sel==key,
      'Updating ribbon detail must keep the existing pane and selected material')
    check(detailed)
    if not detailed then
      assert(UI.on_click{element=chart_control(p,'deselect'),player_index=p.index})
      assert(not storage.ui[p.index].sel)
      check(false)
    end
    s.ribbon_stage=detailed and 'detailed' or 'hide-overview-bands'
  elseif s.ribbon_stage=='hide-overview-bands' or s.ribbon_stage=='show-overview-bands' then
    local show=s.ribbon_stage=='show-overview-bands'
    local old_pane=SK.scroll_pane(panel())
    settings.global[band_setting]={value=show}
    script.get_event_handler(defines.events.on_runtime_mod_setting_changed){
      setting=band_setting,setting_type='runtime-global'}
    assert(old_pane==SK.scroll_pane(panel()) and not storage.ui[p.index].sel,
      'Updating map bands must keep the existing pane and selection')
    assert((#overview_paths().children>0)==show,'Overview bands must follow the map setting')
    local map=overview_paths().parent
    assert(chart_control(p,'overview_jump',key) and map.ssk_viewport_outline.visible,
      'The overview must keep its clickable nodes and viewport outline')
    assert(chart_control(p,'node',key),'The main chart must remain available')
    if show then check(false) end
    s.ribbon_stage=show and 'isolate-copper-ore' or 'overview-bands-off'
  elseif s.ribbon_stage=='isolate-copper-ore' then
    local us=storage.ui[p.index]
    local hidden='item/copper-plate'
    us.hidden[hidden]=true
    UI.refresh(p)
    local dot=assert(chart_control(p,'overview_jump','item/copper-ore'),'Expected a visible isolated producer')
    assert(UI.on_click{element=dot,player_index=p.index})
    check(false)
    for _,band in ipairs(overview_paths().children) do
      assert(band.type~='sprite' or band.sprite:sub(-4)~=string.format('-c%02d',Palette.OVERVIEW_DIM),
        'An isolated selection must keep unrelated bands in colour')
    end
    s.ribbon_stage='isolated'
  elseif s.ribbon_stage=='restore-isolated' then
    local us=storage.ui[p.index]
    us.hidden['item/copper-plate']=nil
    us.sel=nil
    UI.refresh(p)
    check(false)
    s.ribbon_stage='done'
  else
    local name='sankey-ribbons-'..s.ribbon_stage..'.png'
    s.ribbon_modes=s.ribbon_modes or {}
    s.ribbon_modes[s.ribbon_stage]=name
    if RibbonCheck and s.ribbon_stage~='overview-bands-off' then
      local color=Palette.material(key)
      local colors=s.ribbon_stage=='isolated' and {Palette.muted(color)} or {color,Palette.OVERVIEW_DIM}
      s.overview_witnesses=s.overview_witnesses or {}
      s.overview_witnesses[name]=RibbonCheck.overview_witness(overview_paths(),colors)
    end
    game.take_screenshot{player=p,path='gui-interaction/'..name,resolution={1920,1080},show_gui=true,force_render=true}
    local next_stage={compact='enable',detailed='disable',['overview-bands-off']='show-overview-bands',
      isolated='restore-isolated'}
    s.ribbon_stage=next_stage[s.ribbon_stage]
  end
  s.next_tick=game.tick+20
  return true
end

local function capture_toolbar_status(UI,p,s)
  if s.toolbar_status=='done' then return false end
  local budget=Budget
  local function panel()
    return p.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_sankey.ssk_chart
  end
  local function notice()
    local rows=panel().ssk_bar.ssk_toolbar_strip.ssk_toolbar_rows
    local toolbar=rows.ssk_toolbar_main
    local middle=toolbar.ssk_toolbar_middle
    local index=middle.get_index_in_parent()
    assert(#rows.children==1 and not panel().ssk_size_notice,'The status added a heading row')
    assert(toolbar.children[index-1].tags.ssk_sk=='preset' and toolbar.children[index+1].name=='ssk_toolbar_actions',
      'The Full Sankey status must be between the filters and zoom controls')
    return middle.ssk_size_notice
  end
  if not s.toolbar_status then
    settings.get_player_settings(p)['ssk-live-sankey-overview']={value=false}
    open(UI,p,'sankey','sprites')
    s.toolbar_height=SK.scroll_pane(panel()).style.minimal_height
    s.toolbar_budget_links=budget.links
    budget.links=8
    UI.refresh(p)
    local element=notice()
    assert(element.visible and element.caption[1]=='production-flow.sankey-size-limited')
    assert(SK.scroll_pane(panel()).style.minimal_height==s.toolbar_height,'The status must preserve chart height')
    s.toolbar_status='capture'
  elseif s.toolbar_status=='capture' then
    s.toolbar_screenshot='sankey-toolbar-status.png'
    game.take_screenshot{player=p,path='gui-interaction/'..s.toolbar_screenshot,resolution={1920,1080},
      show_gui=true,force_render=true}
    s.toolbar_status='minimum'
  elseif s.toolbar_status=='minimum' then
    local dimensions=UI.dimensions
    UI.dimensions=function() return 880,495 end
    local us=storage.ui[p.index]
    us.view='overview'
    us.hidden['item/copper-plate']=true
    budget.nodes, s.toolbar_budget_nodes=2, budget.nodes
    UI.open(p)
    UI.dimensions=dimensions
    assert(notice().visible and notice().parent.tooltip, 'The minimum window must keep the notice tooltip')
    assert(Check.assert_show_hidden_position(panel()), 'The minimum toolbar lost the restore action')
    s.toolbar_status='capture-minimum'
  elseif s.toolbar_status=='capture-minimum' then
    s.toolbar_minimum_screenshot='sankey-toolbar-status-minimum.png'
    game.take_screenshot{player=p,path='gui-interaction/'..s.toolbar_minimum_screenshot,resolution={1920,1080},
      show_gui=true,force_render=true}
    s.toolbar_status='restore'
  else
    budget.links,budget.nodes=s.toolbar_budget_links,s.toolbar_budget_nodes
    open(UI,p,'sankey','sprites')
    assert(not notice().visible and SK.scroll_pane(panel()).style.minimal_height==s.toolbar_height)
    s.toolbar_status='done'
  end
  s.next_tick=game.tick+20
  return true
end

local function capture_rate_card(UI,p,s)
  if s.card_stage=='done' then return false end
  local key='item/iron-plate'
  local us=storage.ui[p.index]
  local function click(button)
    assert(UI.on_click{element=button,player_index=p.index})
  end
  local function selection()
    return assert(find(p.gui.screen.ssk_main,function(el)return el.name=='ssk_selected_material' end))
  end
  local function check_unselected()
    local empty=selection()
    assert(not us.sel and empty.ssk_selection_empty and empty.ssk_selection_prompt and not empty.ssk_selected_scroll
      and not empty.ssk_selection_header_divider and not empty.ssk_selection_actions and not p.gui.screen.ssk_rate_card,
      'The desktop empty state must contain only the heading and prompt')
  end
  if not s.card_stage then
    us=open(UI,p,'sankey','poly')
    s.card_fixture=true
    local period=p.gui.screen.ssk_main.ssk_window_bar.ssk_period_picker
    period.selected_index=2
    assert(UI.on_selection{element=period,player_index=p.index} and us.period==Sampler.DEFAULT_PERIOD)
    check_unselected()
    click(chart_control(p,'node',key))
    local pinned=selection()
    click(chart_control(p,'deselect'))
    assert(not pinned.valid,'Clearing must remove the previous inspector')
    check_unselected()
    s.card_stage='empty'
  elseif s.card_stage=='select_rate' then
    local bar=chart_control(p,'node',key)
    assert(helpers.table_to_json(bar.tooltip):find('recipe-details-more',1,true),'Material hover preview lost its compact list')
    click(bar)
    local body=card_body(selection())
    assert(us.sel==key and not p.gui.screen.ssk_rate_card and body.ssk_card_net_plot)
    local used=assert(body.ssk_rate_card_used_by)
    local made=assert(body.ssk_rate_card_made_by)
    assert(used.column_count==3 and #used.children==15,'Used by must display all four recipes')
    assert(made.column_count==3 and helpers.table_to_json({made.children[5].caption}):find('[item=iron-ore]',1,true))
    local expected={['iron-gear-wheel']=true,['electronic-circuit']=true,inserter=true,['transport-belt']=true}
    for i=4,#used.children,3 do
      local machine,item,recipe=used.children[i],used.children[i+1],used.children[i+2]
      local item_caption=helpers.table_to_json({item.caption})
      local name=item_caption:match('%[item=([^%]]+)%]')
      local flow=helpers.table_to_json({recipe.caption})
      assert(expected[name] and flow:find(' → ',1,true) and flow:find('[item=iron-plate]',1,true)
        and flow:find('[item='..name..']',1,true),
        'Used by must show the destination item and the complete recipe flow')
      expected[name]=nil
      assert(machine.style.horizontal_align=='right' and item.style.horizontal_align=='right'
        and recipe.style.horizontal_align=='right','Recipe table entries must align right')
    end
    s.card_consumers=4
    s.card_stage='rates'
  elseif s.card_stage=='scroll_recipes' then
    local card=selection()
    card.ssk_selected_scroll.scroll_to_element(card_body(card).ssk_rate_card_used_by,'in-view')
    s.card_stage='recipes'
  elseif s.card_stage=='open_menu' then
    click(chart_control(p,'selection_actions'))
    s.card_stage='menu'
  elseif s.card_stage=='stop' then
    local panel=p.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_sankey.ssk_chart
    local height=SK.scroll_pane(panel).style.minimal_height
    click(chart_control(p,'hide'))
    assert(not us.sel and us.hidden[key])
    local restore=Check.assert_show_hidden_position(panel)
    assert(SK.scroll_pane(panel).style.minimal_height==height,'Hiding a material changed the chart height')
    click(restore)
    assert(not next(us.hidden) and not find(panel,function(el)return el.tags.ssk_sk=='unhide_all' end))
    click(chart_control(p,'node',key))
    click(chart_control(p,'selection_actions'))
    s.stopped=true
    us.live=true
    UI.refresh(p,true)
    local pinned=selection()
    local body=card_body(pinned)
    local history_caption=body.ssk_rate_card_history.caption
    assert(tonumber(history_caption[2][2])==20,'The default 10-minute chart needs a 20-minute card history')
    local history=History.card_rates(us.sidx,1200,key)
    assert(history.points[1].made>0 and history.points[#history.points].made==0,
      'The stopped fixture must have production before the current 10-minute window')
    assert(us.sel==key and not find(p.gui.screen.ssk_main,function(el)
      return el.tags.ssk_sk=='node' and el.tags.key==key
    end),'Fixture must make the selected bar disappear')
    assert(body.ssk_card_rates_plot and body.ssk_card_net_plot
      and not pinned.ssk_selection_actions.ssk_selection_more.enabled
      and helpers.table_to_json(body.children[2].caption):find('sankey-selection-no-bar',1,true),
      'Card must retain history and deactivate edits when its bar disappears')
    s.card_stage='stopped'
  elseif s.card_stage=='compact' then
    local root=p.gui.screen.ssk_main
    local panel=assert(find(root,function(el)return el.name=='ssk_chart' end))
    local narrow_width=620
    us.live=false
    us.canvas_w,us.canvas_h=narrow_width,320
    root.style.width,root.style.height=narrow_width+48,540
    root.auto_center=true
    UI.refresh(p,false,true)
    local drawer=assert(panel.ssk_selected_material)
    assert(SK.scroll_pane(panel).style.minimal_width==narrow_width and not panel.ssk_body
      and drawer.tags.key==key and drawer.style.top_margin<0 and card_body(drawer).ssk_card_net_plot)
    s.card_stage='narrow'
  elseif s.card_stage=='scroll_narrow' then
    local drawer=selection()
    drawer.ssk_selected_scroll.scroll_to_element(card_body(drawer).ssk_card_net_plot,'in-view')
    s.card_stage='narrow-history'
  elseif s.card_stage=='clear_narrow' then
    local drawer=selection()
    click(chart_control(p,'deselect'))
    assert(not us.sel and not drawer.valid and not find(p.gui.screen.ssk_main,function(el)
      return el.name=='ssk_selected_material'
    end),'Clearing the narrow drawer must leave the chart unobstructed')
    s.card_stage,s.stopped,s.card_fixture='done',nil,nil
  else
    local stage=s.card_stage
    local filename='sankey-rate-card-'..stage..'.png'
    game.take_screenshot{player=p,path='gui-interaction/'..filename,resolution={1920,1080},show_gui=true,force_render=true}
    s.rate_card=s.rate_card or {}
    s.rate_card[stage]=filename
    s.card_stage=({empty='select_rate',rates='scroll_recipes',recipes='open_menu',menu='stop',stopped='compact',narrow='scroll_narrow',
      ['narrow-history']='clear_narrow'})[stage]
  end
  s.next_tick=game.tick+15
  return true
end

local function capture_flyouts(UI,p,s)
  if s.flyout_stage=='done' then return false end
  local function click(element, alt)
    assert(UI.on_click{element=element,player_index=p.index,alt=alt==true})
  end
  local screen=p.gui.screen
  if not s.flyout_stage then
    s.card_fixture=true
    local us=open(UI,p,'sankey','sprites')
    local selected='item/iron-plate'
    click(chart_control(p,'node',selected))
    local panel=screen.ssk_main.ssk_inner.ssk_tabs.content_sankey.ssk_chart
    local docked=assert((panel.ssk_body and panel.ssk_body.ssk_sidebar or panel).ssk_selected_material)
    assert(us.sel==selected and docked.tags.key==selected and not screen.ssk_rate_card,
      ('A regular click must open only the Full Sankey docked card (selected=%s, docked=%s, flyout=%s)')
        :format(tostring(us.sel),tostring(docked.tags.key),tostring(screen.ssk_rate_card~=nil)))
    local anchors={'item/iron-plate','item/iron-ore'}
    for index, key in ipairs(anchors) do
      local target=assert(find(panel,function(el)
        return el.tags.ssk_card_material==key
          and (index==1 and el.tags.part=='bar' or index==2 and el.type=='sprite-button')
      end))
      local tooltip=helpers.table_to_json(target.tooltip)
      assert(tooltip:find('sankey-rate-card-click',1,true) and tooltip:find('rate-card-alt-click',1,true))
      click(target,true)
      local card=assert(screen.ssk_rate_card)
      assert(card.tags.key==key and us.sel==selected and docked.valid,
        'Alt-click must open the material flyout without changing the Full Sankey selection')
      local scroll=card.ssk_rate_card_scroll
      assert(scroll.style.name=='ssk_rate_card_scroll' and scroll.style.horizontally_stretchable)
      if index==1 then
        scroll.style='scroll_pane'
        UI.refresh(p,false,false)
        assert(scroll.style.name=='ssk_rate_card_scroll','Existing flyouts must gain the border on refresh')
        local body=scroll.ssk_rate_card_body
        assert(#body.ssk_rate_card_used_by.children==15,'The Alt-click flyout cut off a consuming recipe')
        s.first_card=card
      else s.second_card=card end
      local pin=card.children[1].ssk_rate_card_pin
      assert(pin.sprite=='utility/track_button_white','The flyout must use Factorio’s pushpin')
      click(pin)
      assert(pin.sprite=='utility/track_button' and pin.toggled)
    end
    assert(s.first_card.valid and s.second_card.valid and s.first_card.name~=s.second_card.name)
    assert(math.abs(s.first_card.location.x-s.second_card.location.x)>=430*p.display_scale,
      'Two pinned cards should open beside one another when the screen has room')
    s.flyout_stage='capture'
  elseif s.flyout_stage=='capture' then
    s.flyouts_screenshot='rate-card-two-pins.png'
    game.take_screenshot{player=p,path='gui-interaction/'..s.flyouts_screenshot,resolution={1920,1080},
      show_gui=true,force_render=true}
    s.flyout_stage='fold'
  elseif s.flyout_stage=='fold' then
    click(s.first_card.children[1].ssk_rate_card_fold)
    assert(s.first_card.tags.folded and s.first_card.children[1].ssk_rate_card_pin.toggled
      and not s.first_card.ssk_rate_card_scroll.visible and s.second_card.ssk_rate_card_scroll.visible)
    s.flyout_stage='capture-folded'
  elseif s.flyout_stage=='capture-folded' then
    s.folded_screenshot='rate-card-folded-pin.png'
    game.take_screenshot{player=p,path='gui-interaction/'..s.folded_screenshot,resolution={1920,1080},
      show_gui=true,force_render=true}
    s.flyout_stage='unfold'
  elseif s.flyout_stage=='unfold' then
    click(s.first_card.children[1].ssk_rate_card_fold)
    assert(s.first_card.ssk_rate_card_scroll.visible and not s.first_card.tags.folded
      and s.first_card.children[1].ssk_rate_card_pin.toggled)
    s.flyout_stage='preview'
  elseif s.flyout_stage=='preview' then
    local close=assert(find(s.first_card,function(el) return el.tags.ssk_rate_card=='close' end))
    click(close)
    assert(not s.first_card.valid and s.second_card.valid,'Closing one pin closed another')
    open(UI,p,'sankey','sprites')
    click(chart_control(p,'node','item/iron-plate'))
    local selection=assert(find(screen.ssk_main,function(el) return el.name=='ssk_selected_material' end))
    click(assert(recipe_machine(selection,'used_by')))
    local preview=assert(screen.ssk_machine_preview)
    assert(find(preview,function(el) return el.type=='camera' and el.surface_index==p.surface.index end))
    s.flyout_stage='capture-preview'
  elseif s.flyout_stage=='capture-preview' then
    s.preview_screenshot='rate-card-machine-preview.png'
    game.take_screenshot{player=p,path='gui-interaction/'..s.preview_screenshot,resolution={1920,1080},
      show_gui=true,force_render=true}
    s.flyout_stage='jump'
  else
    local preview=assert(screen.ssk_machine_preview)
    click(assert(find(preview,function(el) return el.tags.ssk_machine_status=='jump' end)))
    assert(p.centered_on and p.centered_on.name=='assembling-machine-2','Jump did not select the previewed machine')
    assert(not screen.ssk_machine_preview and s.second_card.valid)
    click(assert(find(s.second_card,function(el) return el.tags.ssk_rate_card=='close' end)))
    s.card_fixture=nil
    s.flyout_stage='done'
    open(UI,p,'sankey','sprites')
  end
  s.next_tick=game.tick+20
  return true
end

function T.tick(UI)
  local p=game.get_player(1)
  if not p or not p.connected then return end
  if p.controller_type==defines.controllers.cutscene then p.exit_cutscene();return end
  if not storage.gui_interaction then
    local preferences=settings.get_player_settings(p)
    if preferences['ssk-live-sankey-overview'] then
      preferences['ssk-live-sankey-overview']={value=false}
    end
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
    if not broken and capture_viewport_modes(UI,p,s) then return end
    if not broken and capture_ribbon_modes(UI,p,s) then return end
    if not broken and capture_rate_card(UI,p,s) then return end
    if not broken and capture_toolbar_status(UI,p,s) then return end
    if not broken and capture_flyouts(UI,p,s) then return end
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
      expected_obstruction=broken,engine_mouse_input=false,removed_material_check=not broken,fixture='vanilla synthetic rates',
      viewport_modes=s.viewport_modes,ribbon_modes=s.ribbon_modes,rate_card=s.rate_card,card_consumers=s.card_consumers,
      overview_witnesses=s.overview_witnesses,toolbar_screenshot=s.toolbar_screenshot,
      toolbar_minimum_screenshot=s.toolbar_minimum_screenshot,flyouts_screenshot=s.flyouts_screenshot,
      preview_screenshot=s.preview_screenshot,folded_screenshot=s.folded_screenshot}
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
