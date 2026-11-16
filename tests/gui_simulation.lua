-- Private main-menu simulation fixture. Mouse events go through the engine's
-- hit testing and the release control.lua event handler, never direct callbacks.
local T={}
local SK=require('scripts.sankey_ui')
local Sampler=require('scripts.sampler')
local Graph=require('scripts.graph')
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
  local canvas=assert(frame.ssk_sp.ssk_canvas)
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
  frame.ssk_sp.scroll_to_element(e)
  s.caption='GUI_SIMULATION_'..s.index;e.caption=s.caption
  assert(width==length(e,'width') and height==length(e,'height'),'Caption changed icon dimensions')
  emit{stage='open',case=c,key=s.key,expected=s.expected,before=s.before,
    icon_width=width,icon_height=height,column_rows=#best,virtual_scale=p.display_scale}
end
function T.install()
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
          helpers.write_file('gui-simulation/results.json',helpers.table_to_json({cases=s.results,
            engine_mouse_input=true,os_mouse_input=false,virtual_player_scale=game.get_player(s.player).display_scale,
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
