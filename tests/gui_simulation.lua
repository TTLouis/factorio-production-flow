-- Private main-menu simulation fixture. Mouse events go through the engine's
-- hit testing and the release control.lua event handler, never direct callbacks.
local T={}
local SK=require('scripts.sankey_ui')
local Sampler=require('scripts.sampler')
local Graph=require('scripts.graph')
local UI=require('scripts.ui')
local W,H=880,440
local recipes={'iron-plate','copper-plate','iron-gear-wheel','copper-cable','electronic-circuit',
  'automation-science-pack','inserter','transport-belt','logistic-science-pack'}
local cases={}
for _,renderer in ipairs({'poly','sprites'}) do
  for _,tab in ipairs({'balance','focus','sankey'}) do
    for _,which in ipairs({'top','middle','bottom'}) do
      cases[#cases+1]={tab=tab,renderer=renderer,which=which}
    end
  end
end

local function scroll_input(s)
  local p=game.get_player(s.player)
  local sim=game.simulation
  local index=s.scroll_step or 1
  local frame=p.gui.screen.ssk_main
  local chart=storage.ui[p.index]
  local v=chart and chart.chart_viewport
  local setting='ssk-live-sankey-overview'
  local preferences=settings.get_player_settings(p)
  local function set_overview(enabled)
    preferences[setting]={value=enabled}
    local handler=script.get_event_handler(defines.events.on_runtime_mod_setting_changed)
    handler{player_index=p.index,setting=setting,setting_type='runtime-per-user'}
  end
  local function check_native_scroll(window)
    local panel=window.ssk_inner.ssk_tabs.content_sankey.ssk_chart
    local pane=SK.scroll_pane(panel)
    local map=panel.ssk_body.ssk_sidebar.ssk_overview.ssk_overview_map
    assert(pane.vertical_scroll_policy=='auto-and-reserve-space' and pane.horizontal_scroll_policy=='auto',
      'Native scrolling must own both axes after opting out')
    assert(not panel.ssk_body.ssk_viewport and not map.ssk_viewport_outline,
      'Disabled view must keep the overview without a viewport box')
  end
  local function aim(axis)
    local thumb=assert(p.gui.screen['ssk_scroll_thumb_'..axis])
    assert(thumb.grip.drag_target==thumb, 'Scrollbar must have its own drag target')
    local chart=frame.ssk_inner.ssk_tabs.content_sankey.ssk_chart.ssk_body.ssk_viewport
    local track=axis=='x' and chart.ssk_scroll_x or chart.ssk_viewport_row.ssk_scroll_y
    local wrapper=track.children[5]
    local sprite=wrapper.children[1]
    local caption='Rendered scrollbar '..axis
    -- Mark the rendered sprite for native hit testing independently of the target.
    local marker=wrapper.add{type='label',caption=caption,ignored_by_interaction=true}
    marker.style.width,marker.style.height=sprite.style.minimal_width,sprite.style.minimal_height
    sprite.style.right_margin=-sprite.style.minimal_width
    local position=assert(sim.get_widget_position{type='label',text=caption})
    marker.destroy()
    sprite.style.right_margin=0
    return position
  end
  if index==1 then
    p.gui.screen.gui_simulation.destroy()
    storage.ui[p.index]={tab_id='sankey',view='detail',preset='all',layout='clean',period=600,
      renderer='sprites',show_labels=false,live=false,chart_zoom=2.5}
    UI.open(p)
    chart=storage.ui[p.index]
    chart.canvas_h=400
    UI.refresh(p,false,false,true,true)
    assert(preferences[setting].value==true and chart.chart_viewport,'Live overview must default to on')
  elseif index==2 then
    assert(v.max_x>144 and v.max_y>144,'Scrollbar fixture needs overflow on both axes')
    s.scroll_home=frame.location
    s.main_window_moves=0
    s.scroll_cursor=aim('x')
    sim.move_cursor{position=s.scroll_cursor,speed=10000}
  elseif index==3 or index==9 then
    sim.mouse_down()
  elseif index==4 or index==10 then
    local c=s.scroll_cursor
    sim.move_cursor{position={x=c.x+2,y=c.y+(index==10 and 2 or -2)},speed=10000}
  elseif index==5 then
    assert(v.x>0 and frame.location.x==s.scroll_home.x and s.main_window_moves==0,
      'Horizontal drag did not pan or moved the main window at the start')
    s.first_drag_x=v.x
    local c=s.scroll_cursor
    sim.move_cursor{position={x=c.x+3,y=c.y},speed=10000}
  elseif index==6 then
    assert(v.x>s.first_drag_x,'Horizontal thumb must keep moving while held: '
      ..helpers.table_to_json{x=v.x,before=s.first_drag_x})
    s.before_refresh_x=v.x
    UI.refresh(p,false,false,true,true)
    assert(chart.chart_viewport~=v,'Fixture must replace the viewport during the drag')
    log('SCROLL REFRESH '..helpers.table_to_json{x=v.x,after=chart.chart_viewport.x,location=frame.location})
    local c=s.scroll_cursor
    sim.move_cursor{position={x=c.x+4,y=c.y},speed=10000}
  elseif index==7 or index==11 then
    sim.mouse_up()
  elseif index==8 then
    assert(v.x>s.before_refresh_x and v.y==0,'Horizontal thumb must keep moving after a chart refresh: '
      ..helpers.table_to_json{x=v.x,y=v.y,before=s.before_refresh_x,location=frame.location,home=s.scroll_home})
    assert(frame.location.x==s.scroll_home.x and frame.location.y==s.scroll_home.y,'Window moved during horizontal scroll')
    s.scroll_x=v.x
    s.scroll_cursor=aim('y')
    sim.move_cursor{position=s.scroll_cursor,speed=10000}
  elseif index==12 then
    assert(v.x==s.scroll_x and v.y>0,'Vertical thumb drag must change only vertical pan')
    assert(frame.location.x==s.scroll_home.x and frame.location.y==s.scroll_home.y,'Window moved during vertical scroll')
    assert(s.main_window_moves==0,'A scroll drag must never deliver a native main window movement event')
    s.scroll_y=v.y
    sim.move_cursor{position=aim('y'),speed=10000}
  elseif index==13 then
    p.zoom=1
    sim.control_press{control='zoom-out',notify=false}
    sim.control_press{control='ssk-sankey-scroll-right',notify=false}
  elseif index==14 then
    assert(p.zoom==1,'The world zoomed while the mouse was over a scrollbar grip')
    local x,y=math.min(v.max_x,s.scroll_x+48),math.min(v.max_y,s.scroll_y+48)
    assert(v.x==x and v.y==y,'Wheel actions must move the viewport on both axes')
    s.after_wheel={x=v.x,y=v.y}
    sim.control_press{control='ssk-sankey-page-right',notify=false}
  elseif index==15 then
    assert(v.x==math.min(v.max_x,s.after_wheel.x+v.w) and v.y==s.after_wheel.y,
      'Page Down must move one horizontal viewport: '
      ..helpers.table_to_json{x=v.x,y=v.y,previous=s.after_wheel,maximum=v.max_x,width=v.w})
    s.page_right_x=v.x
    sim.control_press{control='ssk-sankey-page-left',notify=false}
  elseif index==16 then
    assert(v.x==math.max(0,s.page_right_x-v.w) and v.y==s.after_wheel.y,
      'Page Up must move one horizontal viewport')
    local title=frame.ssk_window_bar.children[1]
    title.caption='Production Flow drag test'
    s.title_cursor=assert(sim.get_widget_position{type='label',text=title.caption})
    s.scroll_window_moves=s.main_window_moves
    sim.move_cursor{position=s.title_cursor,speed=10000}
  elseif index==17 or index==21 then
    sim.mouse_down()
  elseif index==18 then
    local c=s.title_cursor
    sim.move_cursor{position={x=c.x+0.5,y=c.y+0.5},speed=10000}
  elseif index==19 or index==23 then
    sim.mouse_up()
  elseif index==20 then
    assert(s.main_window_moves>s.scroll_window_moves and frame.location.x>s.scroll_home.x,
      'The actual title bar must still move the window')
    s.moved_home=frame.location
    s.title_window_moves=s.main_window_moves
    s.scroll_cursor=aim('x')
    s.moved_scroll_x=v.x
    sim.move_cursor{position=s.scroll_cursor,speed=10000}
  elseif index==22 then
    local c=s.scroll_cursor
    sim.move_cursor{position={x=c.x+0.5,y=c.y},speed=10000}
  elseif index==24 then
    assert(v.x>s.moved_scroll_x and frame.location.x==s.moved_home.x and frame.location.y==s.moved_home.y
      and s.main_window_moves==s.title_window_moves,
      'Scrollbar must stay aligned and isolate movement after dragging the title bar')
    local c=aim('x')
    sim.move_cursor{position={x=c.x,y=c.y-2},speed=10000}
  elseif index==25 then
    p.zoom=1
    s.repeat_x,s.repeat_y=v.x,v.y
    -- A simulated wheel detent is control_down. control_press also sends a
    -- release, which releases the simulator's held modifiers.
    sim.control_down{control='ssk-fixture-hold-shift',notify=false}
    sim.control_down{control='zoom-out',notify=false}
  elseif index==26 then
    assert(p.zoom==1,'The world zoomed while the mouse was over the chart')
    assert(v.x==math.min(v.max_x,s.repeat_x+48) and v.y==s.repeat_y,
      'First horizontal wheel input must only change horizontal pan')
    sim.control_down{control='zoom-out',notify=false}
  elseif index==27 then
    assert(p.zoom==1,'Repeated wheel input must keep world zoom steady')
    assert(v.x==math.min(v.max_x,s.repeat_x+96) and v.y==s.repeat_y,
      'Repeated horizontal wheel input must keep panning horizontally')
    s.before_left=v.x
    sim.control_down{control='zoom-in',notify=false}
  elseif index==28 then
    assert(v.x==math.max(0,s.before_left-48) and v.y==s.repeat_y and p.zoom==1,
      'Reversing the wheel while Shift stays held must pan left without world zoom')
    sim.control_up{control='ssk-fixture-hold-shift',notify=false}
    sim.control_press{control='zoom-in',notify=false}
  elseif index==29 then
    assert(v.y==math.max(0,s.repeat_y-48) and p.zoom==1,
      'An unmodified wheel tick over the chart must scroll vertically without world zoom')
    local other=sim.create_test_player{name='viewport-default-player'}
    set_overview(false)
    assert(not chart.chart_viewport and p.gui.screen.ssk_main==frame,'Disabling must rebuild only the chart')
    assert(not p.gui.screen.ssk_scroll_thumb_x and not p.gui.screen.ssk_scroll_thumb_y,
      'Disabling live overview must remove scrollbar targets')
    check_native_scroll(frame)
    assert(other.mod_settings[setting].value==true and p.mod_settings[setting].value==false,
      'Disabling the setting changed another player preference')
    set_overview(true)
    assert(chart.chart_viewport and p.gui.screen.ssk_main==frame,'Enabling must restore the viewport')
    UI.close(p)
    sim.move_cursor{position={x=0,y=0},speed=10000}
  elseif index==30 then
    p.zoom=1
    sim.control_press{control='zoom-in',notify=false}
  elseif index==31 then
    assert(p.zoom>1,'World zoom must still work with the chart closed')
    s.scroll_evidence={thumb_drag={x=s.scroll_x,y=s.scroll_y},after_wheel=s.after_wheel,window_held=true,
      main_window_move_events=s.scroll_window_moves,title_drag_preserved=true,drag_survived_refresh=true,horizontal_paging=true,
      repeated_horizontal_wheel=true,world_zoom_isolated=true,
      default_on=true,restored_native=true,per_player=true}
    return true
  end
  s.scroll_step=index+1
end
local function rates()
  local r={recipes={},nodes={}}
  for _,name in ipairs(recipes) do
    local recipe=prototypes.recipe[name]
    if recipe then
      local cps=name=='iron-plate' and 8 or name=='copper-plate' and 6 or 1
      r.recipes[name]={cps=cps,normal_cps=cps}
      for _,side in ipairs({'ingredients','products'}) do
        for _,m in pairs(recipe[side]) do
          local key=m.type..'/'..m.name
          local node=r.nodes[key] or {prod=0,cons=0};r.nodes[key]=node
          local field=side=='ingredients' and 'cons' or 'prod'
          node[field]=node[field]+cps*(m.amount or ((m.amount_min+m.amount_max)/2))*(m.probability or 1)
        end
      end
    end
  end
  return r,600
end
Sampler.rates=rates
local function emit(value)
  log('GUI SIMULATION '..helpers.table_to_json(value))
end
local function length(e,name)
  return e.style[name=='width' and 'minimal_width' or 'minimal_height']
end
local function selection(s)
  return s.case.tab=='sankey' and s.chart.sel or s.chart.focus
end
local function open(s)
  local p=game.get_player(s.player)
  if p.gui.screen.gui_simulation then p.gui.screen.gui_simulation.destroy() end
  local c=cases[s.index];s.case=c
  local chart={view=c.tab=='sankey' and 'detail' or 'focus',neighborhood=c.tab=='balance',
    focus=c.tab=='balance' and 'item/inserter' or 'item/iron-plate',focus_steps=2,input_depth=1,renderer=c.renderer,period=600,sidx=1,
    preset='all',live=false,show_labels=false,layout='clean',tier_mode='depth',heights='sqrt'}
  local us={tab_id=c.tab,period=600,sidx=1,readability_defaults=true,plain_names_default=true,period_default_10m=true}
  if c.tab=='sankey' then us=chart;us.tab_id=c.tab
  elseif c.tab=='balance' then us.bal_fx=chart else us.fx=chart end
  us.readability_defaults,us.plain_names_default,us.period_default_10m=true,true,true
  storage.ui[p.index]=us;s.chart=chart
  local frame=p.gui.screen.add{type='frame',name='gui_simulation',direction='vertical'}
  frame.style.width,frame.style.height=W+24,H+90
  frame.style.padding=0;frame.location={40,40}
  SK.fill(p,frame,chart,W,H,true)
  local pane=SK.scroll_pane and SK.scroll_pane(frame) or frame.ssk_sp
  local canvas=assert(pane.ssk_canvas)
  local columns={}
  for _,wrapper in ipairs(canvas.children) do
    local child=wrapper.children[1]
    if child and child.type=='sprite-button' and child.tags.ssk_sk=='node'
      and not child.tags.key:find('^recipe/') and not child.tags.key:find('^group/') then
      local x=wrapper.style.left_margin
      local list=columns[x] or {};columns[x]=list
      list[#list+1]={key=child.tags.key,y=wrapper.style.top_margin+child.style.top_margin,element=child}
    end
  end
  local best
  for _,list in pairs(columns) do
    table.sort(list,function(a,b)return a.y==b.y and a.key<b.key or a.y<b.y end)
    if #list>=3 and (not best or #list>#best or (#list==#best and list[1].key<best[1].key)) then best=list end
  end
  assert(best,'Fixture needs three selectable material rows in one column: '..c.tab)
  local target=best[c.which=='top' and 1 or c.which=='middle' and math.ceil(#best/2) or #best]
  s.key=target.key;s.expected=c.tab=='sankey' and target.key or target.key:gsub('#.*$','')
  s.before=selection(s);s.received=nil
  -- Caption enables native widget lookup without replacing the actual icon or
  -- changing its fixed dimensions, sprite, tags, ancestry or event routing.
  local e=target.element;local width,height=length(e,'width'),length(e,'height')
  if chart.chart_viewport then
    local v=chart.chart_viewport
    assert(SK.pan_to(p,frame,chart,e.parent.style.left_margin-v.w/2,e.parent.style.top_margin-v.h/2))
    assert(e.visible, 'Panning must reveal the chart node')
  else
    pane.scroll_to_element(e)
  end
  s.caption='GUI_SIMULATION_'..s.index;e.caption=s.caption
  assert(width==length(e,'width') and height==length(e,'height'),'Caption changed icon dimensions')
  emit{stage='open',case=c,key=s.key,expected=s.expected,before=s.before,
    icon_width=width,icon_height=height,column_rows=#best,virtual_scale=p.display_scale}
end
function T.install()
  for _, name in ipairs({'ssk-sankey-page-left','ssk-sankey-page-right'}) do
    local key=assert(script.get_event_handler(name))
    script.on_event(name,function(e)
      local p=game.get_player(e.player_index)
      log('SCROLL PAGE '..helpers.table_to_json{input=name,open_chart=p.opened==p.gui.screen.ssk_main,
        no_opened=p.opened==nil,target=e.element and e.element.type})
      key(e)
    end)
  end
  local position=assert(script.get_event_handler(defines.events.on_gui_location_changed))
  script.on_event(defines.events.on_gui_location_changed,function(e)
    local s=storage.gui_simulation
    local before=e.element.location
    if s and s.main_window_moves and e.element.name=='ssk_main' then
      s.main_window_moves=s.main_window_moves+1
    end
    position(e)
    if s and s.scroll_step then
      log('SCROLL LOCATION '..helpers.table_to_json{step=s.scroll_step,element=e.element.name,
        before=before,after=e.element.location})
    end
  end)
  local original=assert(script.get_event_handler(defines.events.on_gui_click))
  script.on_event(defines.events.on_gui_click,function(e)
    original(e)
    local s=storage.gui_simulation
    if s and s.phase=='verify' then
      s.received={type=e.element.type,name=e.element.name,tags=e.element.tags,selected=selection(s)}
      emit{stage='actual-click',case=s.case,received=s.received}
    end
  end)
  remote.add_interface('production-flow-gui-simulation',{
    start=function(pi)
      local p=game.get_player(pi);p.force.research_all_technologies();Graph.build()
      storage.gui_simulation={player=pi,index=1,phase='open',ticks=0,results={}}
      emit{stage='start',simulation=game.simulation~=nil,resolution=p.display_resolution,virtual_scale=p.display_scale}
    end,
    tick=function()
      local s=storage.gui_simulation
      if not s or s.done then return end
      s.ticks=s.ticks+1;if s.ticks%15~=0 then return end
      if s.phase=='open' then
        if not cases[s.index] then
          if not scroll_input(s) then return end
          helpers.write_file('gui-simulation/results.json',helpers.table_to_json({cases=s.results,
            engine_mouse_input=true,os_mouse_input=false,virtual_player_scale=game.get_player(s.player).display_scale,
            scroll=s.scroll_evidence,
            fixture='Actual SK.fill in fixed-size isolated chart panel; synthetic vanilla recipe rates'}),false)
          s.done=true;log('GUI SIMULATION NATIVE PASS');return
        end
        open(s);s.phase='move'
      elseif s.phase=='move' then
        local target=game.simulation.get_widget_position{type='text-button',text=s.caption}
        assert(target,'Native widget lookup did not find actual chart icon')
        s.position=target;game.simulation.move_cursor{position=target,speed=10000};s.phase='click'
      elseif s.phase=='click' then
        s.phase='verify';game.simulation.mouse_click()
      else
        local received=s.received
        assert(received and received.type=='sprite-button' and received.tags.key==s.key,
          'Native mouse click hit an obstruction: '..helpers.table_to_json{case=s.case,expected=s.key,received=received})
        assert(received.selected==s.expected,'Actual product click selected wrong material')
        s.results[#s.results+1]={case=s.case,key=s.key,expected=s.expected,before=s.before,
          selected=received.selected,position=s.position,event=received}
        s.index=s.index+1;s.phase='open'
      end
    end
  })
end
return T
