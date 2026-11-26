-- Exercise persisted hover through module reload, configuration changes, and
-- deletion of one player without relying on module-local tables.
return function(handlers)
  local UI,SK,H,C=TREQ('scripts.ui'),TREQ('scripts.sankey_ui'),TREQ('scripts.history_ui'),TREQ('scripts.canvas')
  local p,us=game.players[1],storage.ui[1]
  local function find(e,predicate)
    if predicate(e) then return e end
    for _,child in ipairs(e.children) do local hit=find(child,predicate);if hit then return hit end end
  end
  local function reload(path)
    local old=require;require=TREQ
    local module=dofile(path)
    require=old
    return module
  end
  us.tab_id='focus';local fx=SK.focus_state(us);fx.focus='item/iron-plate';fx.live=true
  UI.open(p)
  local panel=p.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_focus.ssk_chart
  local icon=assert(find(panel,function(e)return e.type=='sprite-button' and e.tags.ssk_sk=='node' end))
  assert(SK.on_hover({element=icon,player_index=p.index},true))
  assert(storage.sk_hover[p.index]==icon,'Hovered GUI reference must be persisted')
  local order,canvas=fx.last_order,panel.ssk_sp.ssk_canvas
  local fresh=reload('scripts/sankey_ui.lua')
  fresh.fill(p,panel,fx,fx.canvas_w,fx.canvas_h,false,true)
  UI.auto_refresh()
  assert(icon.valid and fx.last_order==order and panel.ssk_sp.ssk_canvas==canvas,
    'Reloading mid-hover changed the saved auto-refresh skip decision')
  assert(fresh.on_hover({element=icon,player_index=p.index},false))
  fresh.fill(p,panel,fx,fx.canvas_w,fx.canvas_h,false,true)
  assert(not icon.valid and fx.last_order~=order,'Leaving persisted hover must permit the next refresh')

  local history=p.gui.screen.add{type='frame',name='ssk_history_reload_fixture',direction='vertical'}
  local hs={period=600,sidx=1,bal_height=700}
  local data={start_tick=0,end_tick=6000,seconds=15,bucket_seconds=15,
    points={{start_tick=3000,end_tick=3900,seconds=15,made=10,used=8,net=2,uses={},usage_detail={}}},
    usage_keys={},usage_totals={},stock_supported=true,stock={{tick=3000,count=30,measured=true}}}
  H.fill(p,history,hs,'item/iron-plate',900,700,56,{history=data})
  local target=assert(find(history,function(e)return e.tags.ssk_history_bucket end))
  H.on_hover({element=target,player_index=p.index},true)
  local saved=storage.history_hover[p.index]
  assert(saved.target==target and saved.bands[1].sprite.valid and saved.painter==nil,
    'Saved History hover must retain GUI objects without a painter closure')
  local new_history=reload('scripts/history_ui.lua')
  new_history.on_hover({element=target,player_index=p.index},false)
  for _,band in ipairs(saved.bands) do assert(not band.sprite.visible,'Reloaded leave did not hide a saved band') end
  new_history.on_hover({element=target,player_index=p.index},true)
  local left=saved.bands[1].sprite.parent.style.left_margin
  for _,band in ipairs(saved.bands) do assert(band.sprite.visible and band.sprite.parent.style.left_margin==left) end
  new_history.fill(p,history,hs,'item/iron-plate',900,700,56,{history=data})
  local refreshed=storage.history_hover[p.index]
  assert(refreshed.target==target and target.valid,'Reloaded History refresh lost the persisted target')
  H.on_hover({element=target,player_index=p.index},false)
  for _,band in ipairs(refreshed.bands) do assert(not band.sprite.visible,'Old/new modules disagree on current saved bands') end
  new_history.clear_hover(p.index);history.destroy()

  UI.close(p)
  local overview_setting='ssk-live-sankey-overview'
  local previous_overview=p.mod_settings[overview_setting]
  p.mod_settings[overview_setting]={value=true}
  local scroll={tab_id='sankey',view='detail',preset='all',period=600,renderer='sprites',chart_zoom=2.5,live=true}
  storage.ui[p.index]=scroll
  UI.open(p)
  local frame=p.gui.screen.ssk_main
  local origin={x=180,y=90}
  frame.location=origin
  handlers.on_gui_location_changed({element=frame,player_index=p.index})
  local thumb=assert(p.gui.screen.ssk_scroll_thumb_x)
  assert(thumb.grip.drag_target==thumb and frame.ssk_window_bar.drag_target==frame)
  local move={element=thumb,player_index=p.index}
  local first_location=thumb.tags
  thumb.location={x=first_location.x+16,y=first_location.y+20}
  handlers.on_gui_location_changed(move)
  local first_x=scroll.chart_viewport.x
  assert(frame.location==origin and first_x>0,'Moving the thumb must pan without moving the window')
  local before_refresh=scroll.chart_viewport
  UI.refresh(p,false,false,true,true)
  assert(scroll.chart_viewport~=before_refresh,'Fixture must replace the viewport during a held drag')
  local refreshed_location=thumb.tags
  thumb.location={x=refreshed_location.x+16,y=refreshed_location.y+20}
  handlers.on_gui_location_changed(move)
  local viewport=scroll.chart_viewport
  assert(frame.location==origin and math.abs(viewport.x-2*first_x)<=1 and viewport.y==0,
    'A held thumb must keep the window and initial scroll origin through chart refresh')
  local previous_x,previous_y=viewport.x,viewport.y
  handlers['ssk-sankey-page-right']({player_index=p.index})
  assert(viewport.x==math.min(previous_x+viewport.w,viewport.max_x) and viewport.y==previous_y)
  local paged_x=viewport.x
  handlers['ssk-sankey-page-left']({player_index=p.index})
  assert(viewport.x==math.max(0,paged_x-viewport.w) and viewport.y==previous_y)
  local title_location={x=origin.x+25,y=origin.y}
  local previous_thumb_x=thumb.tags.x
  frame.location=title_location
  handlers.on_gui_location_changed({element=frame,player_index=p.index})
  assert(frame.location==title_location and thumb.tags.x==previous_thumb_x+25,
    'The main window and both scrollbars must move together on a title-bar drag')
  UI.close(p)
  assert(not thumb.valid and not p.gui.screen.ssk_scroll_thumb_y,'Closing the window must remove scrollbar targets')
  p.mod_settings[overview_setting]=previous_overview
  storage.ui[p.index]=us

  local original_item,original_fluid=prototypes.item,prototypes.fluid
  local function without_removed(original)
    return setmetatable({},{__index=function(_,key)
      if key:find('^removed%-') then return nil end
      return original[key]
    end})
  end
  prototypes.item,prototypes.fluid=without_removed(original_item),without_removed(original_fluid)
  local previous={sel=us.sel,fx=us.fx,bal_fx=us.bal_fx}
  us.sel='item/removed-material#use'
  us.fx={focus='fluid/removed-fluid',focus_hist={'item/iron-plate','fluid/removed-fluid'}}
  us.bal_fx={focus='item/removed-material',focus_forward={'item/iron-plate'}}
  storage.ui[98]={sel='recipe/removed-recipe',fx={focus='item/removed-material'}}
  handlers.cc()
  assert(us.sel==nil and us.fx.focus==nil and us.bal_fx.focus==nil and #us.fx.focus_hist==1,
    'Configuration change must sanitize saved states even when the window is closed')
  assert(storage.ui[98].sel==nil and storage.ui[98].fx.focus==nil,
    'Configuration change must sanitize disconnected players too')
  us.sel='recipe/iron-plate';storage.ui[98].sel='transport/exports/item/iron-plate'
  UI.sanitize_saved_states()
  assert(us.sel=='recipe/iron-plate' and storage.ui[98].sel=='transport/exports/item/iron-plate',
    'Valid recipe and internal transport identities must survive sanitation')
  us.sel='group/user-1';UI.sanitize_saved_states();assert(us.sel=='group/user-1')
  storage.ui[98]=nil;us.sel,us.fx,us.bal_fx=previous.sel,previous.fx,previous.bal_fx
  prototypes.item,prototypes.fluid=original_item,original_fluid

  local pi=99
  C.begin(p,200,100);local survivor=storage.canvas[p.index].objs[1]
  C.begin({index=pi,force=p.force},200,100);local removed=storage.canvas[pi].objs[1]
  storage.ui[pi]={bal_watches={}};storage.pgroups=storage.pgroups or {};storage.pgroups[pi]={custom={}}
  storage.material_picker=storage.material_picker or {};storage.material_picker[pi]={names={}}
  storage.sk_hover=storage.sk_hover or {};storage.sk_hover[pi]={valid=false}
  storage.history_hover=storage.history_hover or {};storage.history_hover[pi]={bands={{rect=removed}}}
  storage.sk_render=storage.sk_render or {};storage.sk_render[pi]={};storage.sk_render[pi..':focus']={}
  local other_ui,other_render,other_groups=storage.ui[p.index],storage.sk_render[p.index],storage.pgroups[p.index]
  handlers.on_player_removed{player_index=pi}
  handlers.on_player_removed{player_index=pi}
  for _,name in ipairs({'ui','pgroups','canvas','sk_hover','history_hover','material_picker'}) do
    assert(storage[name][pi]==nil,'Player deletion retained '..name)
  end
  assert(storage.sk_render[pi]==nil and storage.sk_render[pi..':focus']==nil and not removed.valid)
  assert(survivor.valid and storage.ui[p.index]==other_ui and storage.sk_render[p.index]==other_render
    and storage.pgroups[p.index]==other_groups,'Player deletion changed another player')
  local sampler,transfers=TREQ('scripts.sampler'),TREQ('scripts.transfers')
  local old_sampler,old_transfers=sampler.on_surface_deleted,transfers.on_surface_deleted
  local calls={};local deleted={surface_index=77}
  sampler.on_surface_deleted=function(index) assert(index==77);calls[#calls+1]='sampler' end
  transfers.on_surface_deleted=function(event) assert(event==deleted);calls[#calls+1]='transfers' end
  handlers.on_pre_surface_deleted(deleted)
  sampler.on_surface_deleted,transfers.on_surface_deleted=old_sampler,old_transfers
  assert(calls[1]=='sampler' and calls[2]=='transfers' and #calls==2,
    'Surface deletion must dispatch the numeric index before the cargo event')
  UI.open(p)
  print('GUI STATE LIFECYCLE OK: saved hover across reload, configuration sanitation, and isolated repeated player cleanup')
end
