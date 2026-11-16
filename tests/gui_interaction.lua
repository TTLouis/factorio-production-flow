-- Injected into a private mod copy by gui_interaction.py. No OS input.
local T={}
local SK=require('scripts.sankey_ui')
local Sampler=require('scripts.sampler')
local Check=require('scripts.gui_interaction_checks')
local broken=require('scripts.gui_interaction_mode')
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
  us.layout='clean';us.tier_mode='depth';us.heights='sqrt';us.renderer=renderer
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
local function inspect(UI,p,c)
  local root=p.gui.screen.ssk_main
  local canvas=assert(find(root,function(e)return e.name=='ssk_canvas' end))
  local result=Check.inspect(canvas,p.display_scale)
  if broken then assert(#result.obstructions>0,'Historical chart obstruction did not reproduce')
  else Check.assert_clear(result) end
  local samples=result.rows[#result.rows]
  assert(samples,'Fixture needs top, middle and bottom rows in one column')
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
function T.tick(UI)
  local p=game.get_player(1)
  if not p or not p.connected then return end
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
    open(UI,p,c.tab,c.renderer);s.phase='inspect';s.next_tick=game.tick+20
  elseif s.phase=='inspect' then
    s.pending=inspect(UI,p,c);s.phase='handlers';s.next_tick=game.tick+5
  else
    handlers(UI,p,c,s.pending)
    s.results[#s.results+1]=s.pending;s.pending=nil
    s.step=s.step+1;s.phase='open';s.next_tick=game.tick+10
  end
end
return T
