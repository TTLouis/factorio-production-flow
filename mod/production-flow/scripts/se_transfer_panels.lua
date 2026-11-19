-- Native Items and History bodies for the surface-centred SE Transfers view.
-- Dispatch witnesses and measured receipts deliberately remain separate.
local Loc=require("scripts.locale")
local Canvas=require("scripts.canvas")
local History=require("scripts.history")
local Endpoints=require("scripts.transfer_endpoints")
local Tooltip=require("scripts.tooltip")
local Geometry=require("scripts.ribbon_geometry")
local Exchanges=require("scripts.transfer_exchanges")
local Axis=require("scripts.transfer_history_axis")
local HistoryLayout=require("scripts.transfer_history_layout")
local Manifest=require("scripts.transfer_manifest_ui")
local GuiPlot=require("scripts.gui_plot")
local Colors=require("shared.plot_colors")
local P={}
local PAGE=20
local IN={r=.40,g=.67,b=.90,a=1}
local OUT={r=.92,g=.58,b=.30,a=1}
local INBOUND_BARS={
  {kind="received",color=IN},
  {kind="inbound_estimate",color=Colors.inbound_estimate},
  {kind="inbound_dispatch",color=Colors.inbound_dispatch},
}
local TEXT={r=.76,g=.76,b=.76,a=1}
local GRID={r=.34,g=.34,b=.35,a=1}
local STOCK_FILL={r=181/255,g=203/255,b=222/255,a=1}
local STOCK_ESTIMATED={r=67/255,g=106/255,b=126/255,a=1}
local STOCK_OUTLINE={r=82/255,g=97/255,b=109/255,a=1}
local IMPORT_RECEIPT={r=139/255,g=212/255,b=156/255,a=1}

local function label(parent,caption,style,width)
  local e=parent.add{type="label",caption=caption,style=style}
  if width then e.style.width=width end
  return e
end
local function row(parent,name)
  local e=parent.add{type="flow",name=name,direction="horizontal"}
  e.style.vertical_align="center";e.style.horizontal_spacing=8
  return e
end
local function spacer(parent) parent.add{type="empty-widget"}.style.horizontally_stretchable=true end
local function action(parent,icon,tip,tags)
  return parent.add{type="sprite-button",style="tool_button",sprite="utility/"..icon,tooltip=tip,tags=tags}
end
local function number(n) return string.format("%.0f",n or 0) end
local function clock(tick)
  local seconds=math.floor((tick or 0)/60)
  return string.format("%02d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
end
local function amount(items,material,quality)
  if items==nil then return nil end
  local total=0
  for _,item in ipairs(items) do
    if (not material or item.name==material) and (not quality or quality=="all" or (item.quality or "normal")==quality) then
      total=total+(item.count or 0)
    end
  end
  return total
end
local function manifest(items)
  if items==nil then return Loc("se-ui-unknown-manifest") end
  local parts={}
  for _,item in ipairs(items) do parts[#parts+1]=Loc.join(Manifest.item_name(item),"  ",number(item.count)) end
  return #parts>0 and Tooltip.lines(parts) or Loc("se-ui-empty-manifest")
end
local function cargo_cell(parent,items,width,material,quality)
  local count=amount(items,material,quality)
  local tip=manifest(items)
  if count==nil or material or #items==0 then
    label(parent,count and number(count) or "—",nil,width).tooltip=tip
    return
  end
  local cell=row(parent)
  cell.style.width=width
  cell.tooltip=tip
  Manifest.preview(cell,items,width)
end
-- A delivery cannon shot that no delivery chest caught: spilled at the target,
-- or landed where no chest stood. Warned on the main row, not in its detail.
local function no_catcher(record)
  return record.method=="cannon" and record.received==nil and (record.status=="spilled" or record.status=="arrived")
end
local function catcher_warning(parent,width,outcome)
  local cell=row(parent,"no_catcher")
  cell.style.width,cell.style.vertical_align=width,"center"
  cell.tooltip=outcome and Loc.join(Loc("se-ui-no-catcher"),"\n",outcome) or Loc("se-ui-no-catcher")
  local icon=cell.add{type="sprite",sprite="utility/warning_icon",resize_to_sprite=false,ignored_by_interaction=true}
  icon.style.width,icon.style.height=16,16
  return cell
end
local function records(data) return data.records or data.history or {} end
local function window(period,data)
  local seconds=period and period>0 and period or settings.global["ssk-window-seconds"].value
  return data.from_tick or game.tick-seconds*60,data.to_tick or game.tick
end
local function place(e,x,y,w,h)
  e.style.width,e.style.height=w,h
  e.style.left_margin,e.style.top_margin,e.style.bottom_margin=x,y,-(y+h)
  return e
end
local function plot(parent,player,width,height,name)
  local body=parent.add{type="flow",name=name,direction="vertical"}
  body.style.width,body.style.height,body.style.vertical_spacing=width,height,0
  Canvas.clear(player.index)
  local painter=GuiPlot.begin(body,width,height)
  local layer=body.add{type="flow",name="se_panel_targets",direction="vertical"}
  layer.style.width,layer.style.height,layer.style.top_margin=width,height,-height
  layer.style.vertical_spacing=0
  return painter,layer
end
local function hit(layer,x,y,w,h,tip,tags)
  return place(layer.add{type="sprite",sprite="ssk-node-hit",resize_to_sprite=false,tooltip=tip,tags=tags},x,y,math.max(1,w),math.max(1,h))
end
local function history_tags(state,direction)
  return {se_logistics="history",direction=direction,method=state.method,material=state.material,quality=state.quality,return_view="items"}
end
local function summary(parent,state,direction,total,unknown)
  local r=row(parent)
  local caption=label(r,Loc(direction=="imports" and "se-ui-received-imports" or "se-ui-sent-exports"),"grey_label")
  caption.tags=history_tags(state,direction);caption.tooltip=Loc("se-ui-open-history")
  local value=label(r,total~=nil and number(total) or "—","semibold_label")
  value.tags=history_tags(state,direction);value.tooltip=Loc("se-ui-open-history")
  if unknown then label(r,Loc("se-ui-partial-known"),"grey_label") end
  action(r,"search",Loc("se-ui-open-history"),history_tags(state,direction))
end

function P.items(parent,player,surface,period,state,width,height,data)
  parent.clear();data=data or {}
  parent.style.vertical_spacing=4
  local heading=row(parent)
  heading.style.width,heading.style.height=width,24
  label(heading,Loc("se-ui-chest-stock"),"caption_label")
  spacer(heading)
  local latest,scan_tick=P.stock_value(player,surface,state)
  if latest~=nil then
    label(heading,number(latest),"bold_label").tooltip=Loc("se-ui-stock-sample",clock(scan_tick),number(latest))
  end
  local legend=label(heading,Loc("history-measured-estimated","[color=#b5cbde]■[/color]","[color=#436a7e]■[/color]"),"grey_label")
  label(heading,Loc("transfer-import-marker","[color=#8bd49c]■[/color]"),"grey_label").tooltip=Loc("transfer-import-marker-help")
  local first,last=window(period,data)
  local trusted=state.material and (not state.quality or state.quality=="all") and player.force==game.forces.player
  local samples,stock_incomplete={},false
  if trusted then
    local h=History.build(surface.index,period,"item/"..state.material)
    stock_incomplete=h.stock_transport_incomplete==true
    for _,sample in ipairs(h.stock) do
      if sample.tick>=first and sample.tick<=last then samples[#samples+1]=sample end
    end
  end
  legend.tooltip=stock_incomplete and Tooltip.lines({Loc("history-estimates-use-the-recorded-made-minus-used"),"\n\n",
    Loc("transport-flow-partial")}) or Loc("history-estimates-use-the-recorded-made-minus-used")
  local resolution=player.display_resolution
  local screen_height=resolution and (resolution.height or resolution[2]) or height
  local chart_height=math.max(120,math.min(height-60,math.floor(screen_height/(player.display_scale or 1)*.34)))
  local painter,layer=plot(parent,player,width,chart_height,"se_stock_chart")
  local left,right,top,bottom=68,width-16,24,chart_height-32
  local max=1
  for _,sample in ipairs(samples) do max=math.max(max,sample.count) end
  local scale=10^math.floor(math.log(max)/math.log(10))
  max=math.ceil(max/scale)*scale
  painter.line(left,top,left,bottom,GRID,1);painter.line(left,bottom,right,bottom,GRID,1)
  for i=0,4 do
    local y=bottom-(bottom-top)*i/4
    painter.line(left,y,right,y,GRID,1)
    if #samples>0 or i==0 then painter.text(left-8,y,string.format("%.5g",max*i/4),TEXT,"right") end
  end
  for i=0,4 do
    local tick=first+(last-first)*i/4
    painter.text(left+(right-left)*i/4,bottom+16,clock(tick),TEXT,i==0 and "left" or i==4 and "right" or "center")
  end
  local function stock_x(tick) return left+(right-left)*(tick-first)/math.max(1,last-first) end
  local function edge(a,b) return Geometry.round(stock_x(b.boundary and b.tick or (a.tick+b.tick)/2)) end
  local function marker(tick)
    local center=Geometry.round(stock_x(tick))
    return math.max(left,center-3),math.min(right,center+3)
  end
  for i,sample in ipairs(samples) do
    local center=stock_x(sample.tick)
    local previous,following=samples[i-1],samples[i+1]
    local x1=sample.joined and previous and edge(previous,sample) or math.max(left,Geometry.round(center-3))
    local x2=following and following.joined and edge(sample,following) or math.min(right,Geometry.round(center+3))
    if sample.measured then
      x1,x2=marker(sample.tick)
    else
      -- Estimates meet fixed-width physical scans instead of widening them.
      if sample.joined and previous and previous.measured then local _,finish=marker(previous.tick);x1=finish end
      if following and following.joined and following.measured then x2=marker(following.tick) end
    end
    if x1==x2 and sample.measured then x1=math.min(x1,right-1);x2=x1+1 end
    local bar_width=x2-x1
    if bar_width>0 then
      local y=math.min(bottom-1,bottom-(bottom-top)*sample.count/max)
      -- Follow Balance History: estimates bridge only covered production
      -- history; isolated measured scans remain narrow six-pixel markers.
      painter.rect(x1,y,bar_width,bottom-y,sample.measured and STOCK_FILL or STOCK_ESTIMATED)
      painter.line(x1,y,x2,y,STOCK_OUTLINE,1)
      painter.line(x1,y,x1,bottom,STOCK_OUTLINE,1);painter.line(x2,y,x2,bottom,STOCK_OUTLINE,1)
      painter.line(x1,bottom,x2,bottom,STOCK_OUTLINE,1)
      local source=sample.measured and Loc("history-measured-stock") or sample.live and Loc("history-estimated-stock-since-last-scan") or Loc("history-estimated-stock")
      local tip=Loc("history-items",clock(sample.tick),source,number(sample.count))
      if stock_incomplete and not sample.measured then tip=Tooltip.lines({tip,"\n\n",Loc("transport-flow-partial")}) end
      hit(layer,x1,top,bar_width,bottom-top,tip,
        {se_stock_sample=true,measured=sample.measured==true,live=sample.live==true})
    end
  end
  if #samples==0 then
    local caption=not state.material and Loc("se-ui-select-material")
      or not trusted and Loc("se-ui-stock-scope-unavailable") or Loc("se-ui-no-stock-scan")
    painter.text((left+right)/2,(top+bottom)/2,caption,TEXT,"center")
  end
  if trusted then for _,record in ipairs(records(data)) do
    local tick=record.arrival_tick
    local count=record.direction=="imports" and record.received and amount(record.received,state.material,state.quality)
    if tick and tick>=first and tick<=last and count and count>0 then
      local x=math.max(left+1,math.min(right-1,Geometry.round(stock_x(tick))))
      painter.line(x,top,x,bottom,IMPORT_RECEIPT,2)
      painter.rect(x-3,top-3,6,4,IMPORT_RECEIPT)
      hit(layer,math.max(left,x-4),top,math.min(8,right-math.max(left,x-4)),bottom-top,
        Loc("transfer-import-receipt",clock(tick),number(count)),{se_import_receipt=true,tick=tick,count=count})
    end
  end end
  local notes=row(parent,"se_item_summary")
  notes.style.width,notes.style.height,notes.style.horizontal_spacing=width,28,16
  local sent,received,unknown_sent,unknown_received=0,0,data.sent_coverage==false,data.receipt_coverage==false
  for _,record in ipairs(records(data)) do
    if (not state.method or state.method=="all" or record.method==state.method) then
      if record.direction=="exports" and record.tick>=first and record.tick<=last then
        local n=amount(record.sent,state.material,state.quality)
        if n then sent=sent+n else unknown_sent=true end
      elseif record.direction=="imports" then
        local n=amount(record.received,state.material,state.quality)
        if n and record.arrival_tick and record.arrival_tick>=first and record.arrival_tick<=last then received=received+n
        elseif (n==nil or not record.arrival_tick) and record.tick>=first and record.tick<=last then unknown_received=true end
      end
    end
  end
  summary(notes,state,"imports",not unknown_received and received or received>0 and received or nil,unknown_received and received>0)
  summary(notes,state,"exports",not unknown_sent and sent or sent>0 and sent or nil,unknown_sent and sent>0)
  spacer(notes)
  label(notes,Loc("se-ui-window-quantity",clock(first),clock(last)),"grey_label").tooltip=Loc("se-ui-stock-scope-help")
end

local function boundary(record)
  return Exchanges.boundary(record)
end
local function record_time(record) return boundary(record) or record.tick or 0 end
local function shipment_bars(painter,group,x,width,middle,scale)
  local count=0
  for _,bar in ipairs(INBOUND_BARS) do
    if (group[bar.kind] or 0)>0 then count=count+1 end
  end
  local lane=0
  for _,bar in ipairs(INBOUND_BARS) do
    local amount=group[bar.kind] or 0
    if amount>0 then
      local left=math.floor(width*lane/count)
      lane=lane+1
      local right=math.floor(width*lane/count)-(lane<count and 1 or 0)
      local bar_height=math.max(1,scale*amount)
      painter.rect(x+left,middle-bar_height,math.max(1,right-left),bar_height,bar.color)
    end
  end
  if group.sent>0 then painter.rect(x,middle+1,width,math.max(1,scale*group.sent),OUT) end
  if group.unmeasured then
    local center=x+width/2
    painter.line(center-4,middle,center,middle-4,TEXT,1)
    painter.line(center,middle-4,center+4,middle,TEXT,1)
    painter.line(center+4,middle,center,middle+4,TEXT,1)
    painter.line(center,middle+4,center-4,middle,TEXT,1)
  end
end
local function shipment_maximum(group)
  return math.max(group.sent,group.received,group.inbound_estimate or 0,group.inbound_dispatch or 0)
end
local function shipment_tip(group,first,last)
  local parts={Loc("se-ui-history-bucket",clock(first),clock(last),
    group.received_known and number(group.received) or "—",group.sent_known and number(group.sent) or "—")}
  if group.inbound_dispatch_known then
    parts[#parts+1]="\n"
    parts[#parts+1]=Loc("se-ui-history-inbound-dispatch",number(group.inbound_dispatch))
  end
  if group.inbound_estimate_known then
    local retention=string.format("%.1f%%",100*group.inbound_estimate/group.estimated_dispatch)
    parts[#parts+1]="\n"
    parts[#parts+1]=Loc("se-ui-history-inbound-estimate",number(group.inbound_estimate),number(group.estimated_dispatch),retention)
  end
  if group.unmeasured then
    parts[#parts+1]="\n"
    parts[#parts+1]=Loc("se-ui-history-unmeasured")
  end
  return Tooltip.lines(parts)
end
local function remote_name(record)
  local remote=record.remote
  if remote then
    local sf=remote.surface
    if sf and sf.valid then return sf.localised_name or sf.name end
    return remote.name or (remote.zone and remote.zone.name) or Loc("se-ui-unknown-surface")
  end
  return Loc("se-ui-unknown-surface")
end
local function method_name(method)
  if method=="cargo-pod" then return Loc("transport-history-cargo-pods") end
  return Loc(method=="cannon" and "se-ui-cannon" or "se-ui-rocket")
end
local function item_total(items)
  local n=0
  for _,item in ipairs(items or {}) do n=n+(item.count or 0) end
  return n
end
-- What the provider established about the landing; never inferred from Sent.
function P.outcome(record)
  if record.method~="rocket" and record.method~="cannon" or record.direction=="unpaired" then return nil end
  if record.received then
    local sent,got=item_total(record.sent),item_total(record.received)
    if record.sent and got<sent then
      return Loc("se-ui-outcome-loss",clock(record.arrival_tick),number(got),number(sent),number(sent-got))
    end
    return Loc("se-ui-outcome-received",clock(record.arrival_tick),number(got))
  end
  local landed=record.landed_tick
  if record.status=="padless" then return Loc("se-ui-outcome-padless") end
  if record.status=="spilled" then return Loc("se-ui-outcome-spilled",clock(landed or record.tick)) end
  if record.status=="arrived" then return Loc("se-ui-outcome-no-chest",clock(landed or record.tick)) end
  if record.status=="lost" then return Loc("se-ui-outcome-lost") end
  if landed then return Loc("se-ui-outcome-unconfirmed",clock(landed)) end
  return Loc("se-ui-outcome-in-flight")
end
local function receipt_tip(record)
  local parts={Loc("se-ui-dispatched",clock(record.tick))}
  local outcome=P.outcome(record)
  local NL="\n"
  if outcome then parts[#parts+1]=NL;parts[#parts+1]=outcome end
  for _,part in ipairs({NL,Loc("se-ui-sent-manifest"),NL,manifest(record.sent),
    NL,Loc("se-ui-received-manifest"),NL,manifest(record.received)}) do parts[#parts+1]=part end
  return Tooltip.lines(parts)
end
local function record_key(record,index) return record.key or record.id or index end
local function jump(parent,player,endpoint,index,side,key,width)
  local cell=row(parent)
  cell.style.width,cell.style.horizontal_align=width,"center"
  local button=action(cell,"go_to_arrow",Loc(side=="sender" and "se-ui-jump-sender" or "se-ui-jump-receiver"),
    {se_logistics="panel-jump",index=index,side=side,key=key})
  button.enabled=Endpoints.can_jump(player,endpoint)
end

-- Keep space for fixed headers, charts and at least a few rows. On compact
-- windows, scroll the body while the tab strip and filters stay in view.
local BODY_MINIMUM={items={900,300},history={920,360},platforms={900,420}}
function P.viewport(parent,width,height,view)
  local minimum=BODY_MINIMUM[view]
  local min_width,min_height=1,1
  if minimum then min_width,min_height=minimum[1],minimum[2] end
  local pad_x,pad_y,rail=12,8,12
  local w,h=width-2*pad_x,height-2*pad_y
  if min_width>w or min_height>h then
    -- Leave room for the native tab frame's bottom inset so the horizontal rail stays visible.
    height=height-2*pad_y
    h=height-2*pad_y
  end
  local horizontal=min_width>w or (min_height>h and min_width>w-rail)
  local vertical=min_height>h or (horizontal and min_height>h-rail)
  local viewport=parent.add{type="scroll-pane",name="viewport",style="naked_scroll_pane",direction="vertical",
    horizontal_scroll_policy=horizontal and "auto" or "never",vertical_scroll_policy=vertical and "auto" or "never"}
  viewport.style.width,viewport.style.height=width,height
  viewport.style.left_padding,viewport.style.right_padding=pad_x,pad_x
  viewport.style.top_padding,viewport.style.bottom_padding=pad_y,pad_y
  w,h=math.max(min_width,w-(vertical and rail or 0)),math.max(min_height,h-(horizontal and rail or 0))
  local body=viewport.add{type="flow",name="body",direction="vertical",tags={width=w,height=h}}
  body.style.width,body.style.height=w,h
  body.style.vertical_spacing=4
end

function P.history(parent,player,surface,period,state,width,height,data,context)
  data=data or {};state.history=state.history or {}
  local hs=state.history
  local layout=parent.se_history_layout
  if not layout or not layout.tags.shared_history_layout then
    parent.clear()
    layout=parent.add{type="flow",name="se_history_layout",direction="vertical",tags={shared_history_layout=true}}
    if not context then HistoryLayout.strip(layout,"se_history_title") end
    layout.add{type="flow",name="se_history_plot",direction="vertical"}
    label(layout,"","grey_label").name="se_history_note"
    HistoryLayout.strip(layout,"se_history_paging")
    HistoryLayout.columns(layout,"se_history_headers",width-HistoryLayout.SCROLL_GUTTER)
    local scroll=layout.add{type="scroll-pane",name="se_history_log",style="naked_scroll_pane",horizontal_scroll_policy="never",vertical_scroll_policy="auto-and-reserve-space"}
    label(scroll,Loc("se-ui-no-records"),"grey_label").name="se_history_empty"
  end
  layout.style.width,layout.style.height=width,height
  layout.style.vertical_spacing=HistoryLayout.GAP
  local first,last=window(period,data)
  local selected={}
  for _,record in ipairs(records(data)) do selected[#selected+1]=record end
  table.sort(selected,function(a,b) if record_time(a)~=record_time(b) then return record_time(a)>record_time(b) end;return tostring(a.key)<tostring(b.key) end)
  hs._records=selected
  local event_groups=hs.axis=="events" and Exchanges.build(selected,first,last,hs.material,hs.quality) or {}
  local event_page,event_pages,event_start,event_finish=Exchanges.page(event_groups,width-84,hs.event_page)
  hs._event_pages=event_pages
  if hs.event_page then hs.event_page=event_page end
  local title=context or layout.se_history_title
  title.style.width,title.style.height=width,context and 28 or HistoryLayout.STRIP_HEIGHT
  if not title.axis then
    title.clear()
    label(title,Loc("transfers-cargo-timeline"),"subheader_caption_label").name="shipment_heading"
    local description=label(title,"","grey_label")
    description.name="shipment_scope"
    description.style.single_line=true
    spacer(title)
    action(title,"left_arrow",Loc("transfer-exchanges-previous"),{se_logistics="panel-exchange-page",delta=-1}).name="previous_exchanges"
    label(title,"","grey_label").name="exchange_pages"
    action(title,"right_arrow",Loc("transfer-exchanges-next"),{se_logistics="panel-exchange-page",delta=1}).name="next_exchanges"
    Axis.add(title,hs.axis,Loc("se-ui-history-axis-help"))
    action(title,"backward_arrow",Loc("se-ui-return-view"),{se_logistics="panel-return"}).name="go_back"
    action(title,"reset",Loc("se-ui-clear-history-filter"),{se_logistics="panel-reset"}).name="clear_filter"
  end
  local scope
  if hs.route and selected[1] then
    local r=selected[1]
    local direction=Loc(r.direction=="imports" and "se-ui-import" or "se-ui-export")
    scope=Loc("se-ui-route-description",method_name(r.method),direction,remote_name(r))
  elseif hs.direction then
    scope=Loc(hs.direction=="imports" and "se-ui-import" or "se-ui-export")
  elseif hs.method then scope=method_name(hs.method) end
  title.shipment_heading.tooltip=scope
  local description=title.shipment_scope
  description.caption,description.tooltip=scope or "",scope
  description.visible=scope~=nil and width>=680
  if description.visible then description.style.width=width-560 end
  local events=hs.axis=="events"
  title.axis.switch_state=events and "right" or "left"
  title.previous_exchanges.visible,title.exchange_pages.visible,title.next_exchanges.visible=events,events,events
  title.previous_exchanges.enabled,title.next_exchanges.enabled=event_page>1,event_page<event_pages
  title.exchange_pages.caption=Loc("se-ui-page",event_page,event_pages)
  title.go_back.visible=hs.return_view~=nil
  title.clear_filter.visible=(hs.route or hs.direction or hs.method or hs.material or hs.quality or hs.bucket)~=nil
  local chart_height=HistoryLayout.plot_height(height)
  local plot_slot=layout.se_history_plot;plot_slot.clear()
  local painter,layer=plot(plot_slot,player,width,chart_height,"se_history_chart")
  local left,right,top,bottom=68,width-16,20,chart_height-32
  local middle=math.floor((top+bottom)/2)
  local bucket_ticks=math.max(60,math.ceil(math.max(1,last-first)/60/12)*60)
  hs._bucket_ticks=bucket_ticks
  local bins={}
  for _,record in ipairs(hs.axis~="events" and selected or {}) do
    local tick,kind,n,dispatch=Exchanges.observation(record,hs.material,hs.quality)
    if tick and tick>=first and tick<=last and (not n or n>0) then
      local bucket=math.floor(tick/bucket_ticks)*bucket_ticks
      bins[bucket]=bins[bucket] or {received=0,sent=0}
      Exchanges.add_observation(bins[bucket],kind,n,dispatch)
    end
  end
  local maximum=0
  for _,bin in pairs(bins) do maximum=math.max(maximum,shipment_maximum(bin)) end
  local exchanges=event_groups
  hs._exchanges=exchanges
  local chosen
  for _,group in ipairs(exchanges) do
    maximum=math.max(maximum,shipment_maximum(group))
    if group.key==hs.exchange then chosen=group end
  end
  if hs.exchange and not chosen then hs.exchange=nil end
  local has_quantity=maximum>0
  maximum=math.max(1,maximum)
  local magnitude=10^math.floor(math.log(maximum)/math.log(10))
  maximum=math.ceil(maximum/magnitude)*magnitude
  local scale=(middle-top-16)/maximum
  painter.line(left,top,left,bottom,GRID,1);painter.line(left,middle,right,middle,TEXT,1)
  painter.text(left-8,middle,"0",TEXT,"right")
  for i=1,2 do
    if has_quantity and (i==2 or maximum>=2) then
      local count=maximum*i/2
      local offset=(middle-top-16)*i/2
      painter.line(left,middle-offset,right,middle-offset,GRID,1)
      painter.line(left,middle+offset,right,middle+offset,GRID,1)
      painter.text(left-8,middle-offset,"+"..string.format("%.5g",count),TEXT,"right")
      painter.text(left-8,middle+offset,"−"..string.format("%.5g",count),TEXT,"right")
    end
  end
  painter.text(left+4,top+4,Loc("se-ui-received-above"),IN,"left")
  painter.text(left+4,bottom-7,Loc("se-ui-sent-below"),OUT,"left")
  for i=0,hs.axis=="events" and -1 or 4 do
    local tick=first+(last-first)*i/4
    painter.text(left+(right-left)*i/4,bottom+16,clock(tick),TEXT,i==0 and "left" or i==4 and "right" or "center")
  end
  for bucket,bin in pairs(bins) do
    local x1=math.min(right-10,left+(right-left)*(math.max(first,bucket)-first)/math.max(1,last-first))
    local x2=math.max(x1+10,left+(right-left)*(math.min(last,bucket+bucket_ticks)-first)/math.max(1,last-first))
    local bar_width=x2-x1-3
    shipment_bars(painter,bin,x1+1,bar_width,middle,scale)
    hit(layer,x1,top,math.max(1,x2-x1),bottom-top,
      shipment_tip(bin,math.max(first,bucket),math.min(last,bucket+bucket_ticks)),
      {se_logistics="panel-bucket",bucket=bucket})
  end
  if hs.axis=="events" then
    -- Nil follows the newest page as history grows; an explicit page stays put.
    for i=event_start,event_finish do
      local group=exchanges[i]
      local x=right-(event_finish-i+.5)*Exchanges.SLOT
      if group==chosen then painter.rect(x-11,top,22,bottom-top,{r=.28,g=.24,b=.18,a=.35}) end
      shipment_bars(painter,group,x-8,16,middle,scale)
      if (i-event_start)%3==0 then painter.text(x,bottom+16,"#"..i,TEXT,"center") end
      hit(layer,x-11,top,22,bottom-top,shipment_tip(group,group.first_tick,group.last_tick),
        {se_logistics="panel-exchange",exchange=group.key})
    end
  end
  local note=layout.se_history_note
  local is_se=data.provider~="sa"
  local key=Loc(is_se and "se-ui-history-quantity-key" or "se-ui-history-quantity-key-measured")
  note.caption=is_se and Loc.join(key,"\n",Loc("se-ui-history-measurement-limit")) or key
  note.style.width=width
  note.tooltip=Loc(hs.axis=="events" and "transfer-exchange-help" or "se-ui-history-measurement-help")
  note.style.single_line=false
  local note_height=is_se and (width<900 and 60 or 40) or (width<720 and 40 or 20)
  note.style.height=note_height
  local filtered={}
  for index,record in ipairs(selected) do
    local tick=record_time(record)
    if tick>=first and tick<=last and (not chosen or chosen.records[record.key or tostring(index)])
      and (not hs.bucket or (tick>=hs.bucket and tick<hs.bucket+bucket_ticks)) then filtered[#filtered+1]={record=record,index=index} end
  end
  local pages=math.max(1,math.ceil(#filtered/PAGE))
  hs.page=math.max(1,math.min(hs.page or 1,pages));hs._pages=pages
  local paging=layout.se_history_paging;paging.clear()
  paging.style.width=width
  label(paging,Loc("se-ui-shipment-history"),"subheader_caption_label")
  spacer(paging)
  label(paging,Loc("se-ui-record-count",number(#filtered)),"subheader_semibold_label")
  if hs.bucket or hs.exchange then
    label(paging,hs.exchange and Loc("transfer-exchange-selected") or Loc("se-ui-selected-bucket",clock(hs.bucket)),"grey_label")
    action(paging,"reset",Loc("se-ui-clear-time-filter"),{se_logistics="panel-bucket-clear"})
  end
  local previous=action(paging,"left_arrow",Loc("se-ui-previous-page"),{se_logistics="panel-page",delta=-1});previous.enabled=hs.page>1
  label(paging,Loc("se-ui-page",hs.page,pages),"grey_label")
  local next_page=action(paging,"right_arrow",Loc("se-ui-next-page"),{se_logistics="panel-page",delta=1});next_page.enabled=hs.page<pages
  local headers=layout.se_history_headers;headers.clear()
  -- Header and log cells share widths. Leave one 8px gutter before the native
  -- 12px scrollbar rail. The last two cells name the endpoint jump actions.
  local row_width=width-HistoryLayout.SCROLL_GUTTER
  local compact=row_width<540
  local gap=compact and 4 or 8
  local time_width,amount_width,endpoint_width=96,compact and 64 or 80,compact and 60 or 64
  local route_width=math.max(1,row_width-28-time_width-2*(amount_width+endpoint_width)-6*gap)
  headers.style.width=row_width
  local header_row=row(headers)
  header_row.style.height,header_row.style.horizontal_spacing=HistoryLayout.ROW_HEIGHT,gap
  label(header_row,"",nil,28);label(header_row,Loc("se-ui-time"),"bold_label",time_width)
  label(header_row,Loc("se-ui-route-method"),"bold_label",route_width)
  label(header_row,Loc("se-ui-sent"),"bold_label",amount_width)
  label(header_row,Loc("se-ui-received"),"bold_label",amount_width)
  label(header_row,Loc("se-ui-sender"),"bold_label",endpoint_width).style.horizontal_align="center"
  label(header_row,Loc("se-ui-receiver"),"bold_label",endpoint_width).style.horizontal_align="center"
  local scroll=layout.se_history_log
  scroll.style.width,scroll.style.height=width,HistoryLayout.log_height(height,chart_height,note_height,context)
  scroll.se_history_empty.visible=#filtered==0
  local visible_rows=0
  for n=(hs.page-1)*PAGE+1,math.min(hs.page*PAGE,#filtered) do
    visible_rows=visible_rows+1
    local entry=filtered[n];local record,index=entry.record,entry.index
    local key=record_key(record,index)
    local wrapper=scroll["se_shipment_"..visible_rows]
    if not wrapper then wrapper=scroll.add{type="flow",name="se_shipment_"..visible_rows,direction="vertical"} end
    wrapper.visible=true;wrapper.clear()
    wrapper.style.width,wrapper.style.vertical_spacing=row_width,4
    local r=row(wrapper)
    r.style.width,r.style.height,r.style.horizontal_spacing=row_width,HistoryLayout.ROW_HEIGHT,gap
    local expand=action(r,hs.expanded==key and "collapse" or "expand",Loc("se-ui-expand-manifest"),{se_logistics="panel-expand",index=index,key=key})
    expand.toggled=hs.expanded==key
    local time=label(r,clock(record_time(record)),nil,time_width)
    local _,time_kind=boundary(record)
    time.tooltip=Loc(time_kind=="received" and "se-ui-arrival-time" or "se-ui-departure-time")
    local direction=Loc(record.direction=="imports" and "se-ui-import" or record.direction=="exports" and "se-ui-export" or "se-ui-unpaired")
    local route=label(r,Loc("se-ui-route-description",method_name(record.method),direction,remote_name(record)),nil,route_width)
    route.style.single_line=true
    route.tooltip=receipt_tip(record)
    cargo_cell(r,record.sent,amount_width,hs.material,hs.quality)
    if no_catcher(record) then catcher_warning(r,amount_width,P.outcome(record))
    else cargo_cell(r,record.received,amount_width,hs.material,hs.quality) end
    jump(r,player,record.sender,index,"sender",key,endpoint_width)
    jump(r,player,record.receiver,index,"receiver",key,endpoint_width)
    if hs.expanded==key then
      local detail=wrapper.add{type="frame",name="manifest_detail",style="inside_shallow_frame",direction="vertical"}
      detail.style.width,detail.style.padding=row_width,8
      -- No subtitles: one table of item, lost, received. Departure and landing
      -- outcome stay in the route tooltip; an unmeasured "—" cell explains itself.
      local manifests=detail.add{type="flow",name="manifests",direction="vertical"}
      local unknown_tip=record.received==nil and P.outcome(record) or nil
      Manifest.receipt(manifests,"received",record.sent,record.received,row_width-16,number,nil,unknown_tip)
    end
  end
  for i=visible_rows+1,PAGE do
    local wrapper=scroll["se_shipment_"..i]
    if wrapper then wrapper.visible=false end
  end
  -- Retain the native scroll-pane and its row slots during live refresh. The
  -- runtime exposes no pixel scroll-position attribute; never emulate one.
  if hs._scroll_reset then scroll.scroll_to_top();hs._scroll_reset=nil end
end

function P.on_click(e,state,close_all)
  local tags=e.element.tags or {};local a=tags.se_logistics
  if not a or a:sub(1,6)~="panel-" then return false end
  state.history=state.history or {};local hs=state.history
  if a=="panel-bucket" then hs.bucket=hs.bucket~=tags.bucket and tags.bucket or nil;hs.exchange=nil;hs.page=1;hs.expanded=nil;hs._scroll_reset=true
  elseif a=="panel-bucket-clear" then hs.bucket=nil;hs.exchange=nil;hs.page=1;hs.expanded=nil;hs._scroll_reset=true
  elseif a=="panel-exchange" then hs.exchange=hs.exchange~=tags.exchange and tags.exchange or nil;hs.bucket=nil;hs.page=1;hs.expanded=nil;hs._scroll_reset=true
  elseif a=="panel-exchange-page" then hs.event_page=math.max(1,math.min((hs.event_page or hs._event_pages or 1)+(tags.delta or 0),hs._event_pages or 1))
  elseif a=="panel-page" then hs.page=math.max(1,math.min((hs.page or 1)+(tags.delta or 0),hs._pages or 1));hs.expanded=nil;hs._scroll_reset=true
  elseif a=="panel-reset" then state.history={return_view=hs.return_view,axis=hs.axis,_scroll_reset=true}
  elseif a=="panel-return" then
    if hs.return_view=="flow" or hs.return_view=="items" then state.view=hs.return_view end
  elseif a=="panel-expand" then
    local record=(hs._records or {})[tags.index]
    if record and record_key(record,tags.index)==tags.key then local key=record_key(record,tags.index);hs.expanded=hs.expanded~=key and key or nil end
  elseif a=="panel-jump" then
    local record=(hs._records or {})[tags.index]
    if record and record_key(record,tags.index)==tags.key and (tags.side=="sender" or tags.side=="receiver") then
      Endpoints.jump(game.get_player(e.player_index),record[tags.side],close_all)
    end
  else return false end
  return true
end
function P.on_switch(e,state)
  local axis=Axis.selection(e.element)
  if not axis then return false end
  state.history=state.history or {};local hs=state.history
  if (hs.axis or "time")~=axis then
    hs.axis=axis
    hs.bucket,hs.exchange,hs.event_page,hs.page,hs.expanded=nil,nil,nil,1,nil;hs._scroll_reset=true
  end
  return true
end
-- Stock scans are all-quality and player-force only. Return nil for a scope
-- the sampler cannot represent; callers must not display an invented zero.
function P.stock_value(player,surface,state)
  if (state.quality and state.quality~="all") or player.force~=game.forces.player
    or storage.stock_basis~="physical-storage-v2" then return nil end
  local scans=storage.stock or {};local latest=scans[#scans]
  local values=latest and latest.s and latest.s[surface.index]
  if values then
    if state.material then return values["item/"..state.material] or 0,latest.tick end
    local total=0
    for key,count in pairs(values) do if key:sub(1,5)=="item/" then total=total+count end end
    return total,latest.tick
  end
end
return P
