-- Native SE Transfers shell and grouped Sankey. Dispatch is not receipt.
local Loc=require("scripts.locale")
local Data=require("scripts.se_transfer_data")
local Cannons=require("scripts.se_cannons")
local Panels=require("scripts.se_transfer_panels")
local Canvas=require("scripts.canvas")
local Surfaces=require("scripts.surfaces")
local Tooltip=require("scripts.tooltip")
local Endpoints=require("scripts.transfer_endpoints")
local Sampler=require("scripts.sampler")
local Items=require("scripts.transport_items_ui")
local Entities=require("scripts.transport_history_entities")
local GuiPlot=require("scripts.gui_plot")
local Shades=require("shared.ribbon_shades")
local ZoneInfo=require("scripts.se_zone_info")
local UI={}
local VERSION=13
-- Native tab strip plus its 8 px content padding: the same 48 px Balance and
-- Space Age Transfers subtract, so all nested tab frames end on one line.
local TAB_CHROME,STRIP_HEIGHT=48,56
local PAD_X,PAD_Y=12,8
local CENTER_HEIGHT,PORT_INSET=224,8
local ZONE_LINE=20
-- Route card: 2 px frame padding, a 34 px name strip, a 22 px Sent/Received
-- heading, then one row per transport method or per item, as the Flow switch
-- selects (28 px, or taller for a thick ribbon). ROUTE_FIXED is everything but
-- those rows; ROUTE_GAP separates cards. Items mode gives each of the
-- surface's top items (Shades.ITEMS) its own row and merges the rest into a
-- grey "Other items" row.
local ROUTE_STRIP,ROUTE_HEAD,ROUTE_ROW,ROUTE_GAP=34,22,28,12
local ROUTE_FIXED=2+ROUTE_STRIP+ROUTE_HEAD+2
local SENT_W,RECEIVED_W=64,72
local METHOD_ICON={rocket="entity/se-rocket-launch-pad",cannon="entity/se-delivery-cannon"}
local function strip_height(view) return view=="items" and STRIP_HEIGHT or 0 end
local VIEWS={"flow","items","history"}
local METHODS={false,"rocket","cannon"}
local function label(parent,caption,style,width)
  local e=parent.add{type="label",caption=caption,style=style}
  if width then e.style.width=math.max(1,width);e.style.single_line=true end
  return e
end
local function plain(e)
  if defines.rich_text_setting then e.style.rich_text_setting=defines.rich_text_setting.disabled end
  return e
end
local function row(parent,name)
  local e=parent.add{type="flow",name=name,direction="horizontal"};e.style.vertical_align="center";return e
end
local function spacer(parent)parent.add{type="empty-widget"}.style.horizontally_stretchable=true end
local function action(parent,icon,tip,tags)
  return parent.add{type="sprite-button",sprite="utility/"..icon,style="tool_button",tooltip=tip,tags=tags}
end
-- Absolute placement on whole pixels. Height and Y are cancelled separately
-- (with a zero-size reset), because the GUI rounds each length on its own:
-- fractional or combined offsets drifted later items, such as the Exports
-- heading sitting 3 px above Imports.
local function at(parent,x,y,w,h)
  x,y=math.floor(x+.5),math.floor(y+.5)
  w,h=math.max(1,math.floor(w+.5)),math.max(1,math.floor(h+.5))
  local e=parent.add{type="flow",direction="vertical"}
  e.style.width,e.style.height=w,h
  e.style.left_margin,e.style.top_margin,e.style.bottom_margin=x,y,-h
  local reset=parent.add{type="empty-widget",ignored_by_interaction=true,tags={ssk_position_reset=true}}
  reset.style.width,reset.style.height=0,0
  reset.style.left_margin,reset.style.bottom_margin=0,0
  reset.style.top_margin=-y
  return e
end
local function number(n)
  if n==nil then return "—" end
  return (string.format("%.0f",n):reverse():gsub("(%d%d%d)","%1,"):gsub(",$",""):reverse())
end
local function sum(items)
  if items==nil then return nil end
  local n=0;for _,item in ipairs(items) do n=n+item.count end;return n
end
local function material_name(name) return name and ((prototypes.item[name] or {}).localised_name or name) or Loc("se-all-materials") end
local function method_name(method) return method=="cannon" and Loc("se-ui-cannons") or Loc("se-cargo-rockets") end
local function remote_name(group)
  local e=group.remote or group.endpoint or {}
  return e.surface and e.surface.valid and Surfaces.label(e.surface) or e.name or "?"
end
local function route_tags(group,method,state,direction)
  return {se_logistics="history",route=group.id,method=method and method.method or nil,direction=direction}
end
local function method_height(thickness) return math.max(ROUTE_ROW,thickness+6) end
local function route_tip(group,method,state)
  local parts={remote_name(group),"\n",method_name(method.method)," · ",material_name(nil),"\n",
    Loc("se-ui-sent-received",number(sum(method.sent)),number(sum(method.received))),"\n",Loc("se-ui-open-history")}
  for _,item in ipairs(method.sent or method.sent_observed or {}) do
    parts[#parts+1]=Loc.join("\n[item=",item.name,"] ",material_name(item.name)," · ",item.quality,"  ",number(item.count))
  end
  return Tooltip.lines(parts)
end
-- One route's items across all methods, largest ribbon first. Sent and
-- Received stay unknown ("—") unless every shipment's manifest is known, as
-- in the method rows; the ribbon uses the observed sent amount.
local function route_items(group)
  local index,list={},{}
  local function entry(item)
    local key=item.name.."/"..item.quality;local e=index[key]
    if not e then e={name=item.name,quality=item.quality,ribbon=0,received=0};index[key]=e;list[#list+1]=e end
    return e
  end
  for _,item in ipairs(group.sent_observed or {}) do local e=entry(item);e.ribbon=e.ribbon+item.count end
  for _,item in ipairs(group.received_observed or {}) do local e=entry(item);e.received=e.received+item.count end
  table.sort(list,function(a,b)
    if a.ribbon~=b.ribbon then return a.ribbon>b.ribbon end
    if a.received~=b.received then return a.received>b.received end
    if a.name~=b.name then return a.name<b.name end
    return a.quality<b.quality
  end)
  for _,e in ipairs(list) do
    e.sent=group.sent and e.ribbon or nil
    if not group.received then e.received=nil end
  end
  return list
end
local function items_tip(group,title,items)
  local sent,received=0,0
  for _,item in ipairs(items) do
    sent=sent and item.sent and sent+item.sent or nil
    received=received and item.received and received+item.received or nil
  end
  local parts={remote_name(group),"\n",title,"\n",Loc("se-ui-sent-received",number(sent),number(received)),"\n",Loc("se-ui-open-history")}
  if #items>1 then
    for _,item in ipairs(items) do
      parts[#parts+1]=Loc.join("\n[item=",item.name,"] ",material_name(item.name)," · ",item.quality,"  ",number(item.ribbon))
    end
  end
  return Tooltip.lines(parts),sent,received
end
-- Each side's most transported items over all its routes, each item and
-- quality ranked by observed sent amount. The top Shades.ITEMS on a side get
-- rows; an item keeps one colour on both sides; the rest form the grey band.
-- Returns side -> key -> slot, and the ranking for the rebuild signature.
local function item_slots(groups)
  local tops,totals,signature={},{},{}
  for _,side in ipairs({"imports","exports"}) do
    local sums,keys={},{}
    for _,g in ipairs((groups or {})[side] or {}) do
      for _,item in ipairs(route_items(g)) do
        local key=item.name.."/"..item.quality;local e=sums[key]
        if not e then e={ribbon=0,received=0};sums[key]=e;keys[#keys+1]=key end
        e.ribbon=e.ribbon+item.ribbon;e.received=e.received+(item.received or 0)
      end
    end
    table.sort(keys,function(a,b)
      local x,y=sums[a],sums[b]
      if x.ribbon~=y.ribbon then return x.ribbon>y.ribbon end
      if x.received~=y.received then return x.received>y.received end
      return a<b
    end)
    tops[side]={}
    for i=1,math.min(#keys,Shades.ITEMS) do
      local key=keys[i];tops[side][i]=key;signature[#signature+1]=side..":"..key
      local e=totals[key] or {key=key,sides={},ribbon=0};totals[key]=e
      e.sides[side]=true;e.ribbon=e.ribbon+sums[key].ribbon
    end
  end
  -- Items on both sides choose first, then the rest, largest first.
  local entries={};for _,e in pairs(totals) do entries[#entries+1]=e end
  table.sort(entries,function(a,b)
    local x,y=a.sides.imports and a.sides.exports,b.sides.imports and b.sides.exports
    if x~=y then return x and true or false end
    if a.ribbon~=b.ribbon then return a.ribbon>b.ribbon end
    return a.key<b.key
  end)
  local slot=Shades.assign_items(entries);local result={}
  for side,keys in pairs(tops) do result[side]={};for _,key in ipairs(keys) do result[side][key]=slot[key] end end
  return result,signature
end
-- Second-level rows of a route card: transport methods, or the route's items
-- among its side's top items, followed by one grey row for everything else.
local function route_rows(group,side,grouping,slots)
  local rows={}
  if grouping~="items" then
    for index,m in ipairs(group.methods) do
      rows[#rows+1]={name="method_"..index,icon=METHOD_ICON[m.method],caption=method_name(m.method),style="bold_label",
        sent=sum(m.sent),received=sum(m.received),ribbon=sum(m.sent or m.sent_observed) or 0,
        tags=route_tags(group,m,nil,side),tip=route_tip(group,m)}
    end
    return rows
  end
  local items,rest,ribbon=route_items(group),{},0
  for _,item in ipairs(items) do
    local slot=slots[item.name.."/"..item.quality]
    if slot then
      local tip=items_tip(group,Loc.join(material_name(item.name)," · ",item.quality),{item})
      rows[#rows+1]={name="item_"..(#rows+1),item=item.name,quality=item.quality,caption=material_name(item.name),
        sent=item.sent,received=item.received,ribbon=item.ribbon,tip=tip,slot=slot,
        tags={se_logistics="history",route=group.id,direction=side,material=item.name,quality=item.quality}}
    else rest[#rest+1]=item;ribbon=ribbon+item.ribbon end
  end
  if #rest>0 or #items==0 then
    local caption=#items==0 and Loc("se-ui-unknown-contents") or Loc("se-ui-other-items",#rest)
    local tip,sent,received=items_tip(group,caption,rest)
    if #items==0 then sent,received=nil,nil end
    rows[#rows+1]={name="item_other",caption=caption,style="grey_label",sent=sent,received=received,ribbon=ribbon,
      tip=tip,tags=route_tags(group,nil,nil,side)}
  end
  return rows
end

local function build(content,width,height)
  content.clear()
  local panel=content.add{type="flow",name="ssk_se_logistics",direction="horizontal"}
  panel.style.width,panel.style.height,panel.style.horizontal_spacing=width,height,0
  panel.style.vertical_align="top"
  local tabs=panel.add{type="tabbed-pane",name="se_tabs",style="tabbed_pane_with_no_side_padding",tags={se_logistics="tabs"}}
  tabs.style.width,tabs.style.top_margin=width,0
  for _,view in ipairs(VIEWS) do
    local tab=tabs.add{type="tab",caption=Loc(view=="items" and "se-ui-items" or view=="history" and "help-history" or "help-flow")}
    local frame=tabs.add{type="frame",name="se_"..view,style="inside_deep_frame",direction="vertical"}
    frame.style.width,frame.style.height,frame.style.padding=width,height-TAB_CHROME,0
    local scroll_filters=view=="items" and height-TAB_CHROME-STRIP_HEIGHT<64
    if scroll_filters then Panels.viewport(frame,width,height-TAB_CHROME,view) end
    if view=="items" then
      local container=scroll_filters and frame.viewport or frame
      local strip=container.add{type="frame",name="toolbar",style="subheader_frame",direction="vertical",index=1}
      strip.style.height=STRIP_HEIGHT;strip.style.horizontally_stretchable=true
      strip.style.left_padding,strip.style.right_padding=PAD_X,PAD_X
      strip.style.top_padding,strip.style.bottom_padding=PAD_Y,PAD_Y
      local bar=row(strip,"controls")
      bar.style.height=40;bar.style.horizontally_stretchable=true
      label(bar,Loc("se-ui-transport"))
      bar.add{type="drop-down",name="se_method",items={Loc("se-ui-all-transport"),Loc("se-cargo-rockets"),Loc("se-ui-cannons")},selected_index=1,tags={se_logistics="method"}}
      local material=bar.add{type="drop-down",name="se_material",items={Loc("se-all-materials")},selected_index=1,tags={se_logistics="material"},tooltip=Loc("se-material-help")}
      material.style.width=math.min(230,math.floor(width*.22))
      material.visible=false
      label(bar,Loc("se-ui-quality"))
      local quality=bar.add{type="drop-down",name="se_quality",items={Loc("se-ui-all-qualities")},selected_index=1,tags={se_logistics="quality"}}
      quality.style.width=130
    end
    if not scroll_filters then Panels.viewport(frame,width,height-TAB_CHROME-strip_height(view),view) end
    tabs.add_tab(tab,frame)
  end
  -- Use the free right end of the native tab strip, as Space Age Transfers does.
  local heading=row(panel,"heading")
  local heading_w=math.min(320,math.floor(width*.4))
  heading.style.width,heading.style.height=heading_w,36
  heading.style.left_margin,heading.style.right_margin=-(heading_w+PAD_X),PAD_X
  spacer(heading)
  local coverage=label(heading,"","grey_label")
  coverage.name="se_coverage"
  coverage.style.maximal_width,coverage.style.single_line=heading_w-36,true
  coverage.visible=width>=440
  action(heading,"go_to_arrow",Loc("se-ui-jump-surface"),{se_logistics="surface-jump"})
  panel.tags={version=VERSION,width=width,height=height};return panel
end
local function choices(base,player,surface,state)
  local set={};for _,name in ipairs(base.materials or {}) do set[name]=true end
  if player.force==game.forces.player then
    local snapshots=storage.stock or {};local last=snapshots[#snapshots]
    for key in pairs(last and last.s[surface.index] or {}) do local name=key:match("^item/(.+)$");if name then set[name]=true end end
  end
  for _,entry in ipairs((state.endpoints or {}).cannons or {}) do for _,item in ipairs(entry.ready_payload or {}) do set[item.name]=true end end
  for _,entry in ipairs((state.endpoints or {}).receivers or {}) do for _,item in ipairs(entry.stored_items or {}) do set[item.name]=true end end
  if state.material then set[state.material]=true end
  if state.history.material then set[state.history.material]=true end
  local result={};for name in pairs(set) do result[#result+1]=name end;table.sort(result);return result
end
local function item_controls(bar,base,materials,state)
  local names,captions={},{};local selected=1
  if #materials==0 then names={false};captions={Loc("se-all-materials")} end
  for _,name in ipairs(materials) do names[#names+1]=name;captions[#captions+1]=material_name(name);if state.material==name then selected=#names end end
  state.materials=names;bar.se_material.items=captions;bar.se_material.selected_index=selected
  local names_q,captions_q={false},{Loc("se-ui-all-qualities")};local index=1
  local set={normal=true};for _,name in ipairs(base.qualities or {}) do set[name]=true end;if state.quality then set[state.quality]=true end
  local sorted={};for name in pairs(set) do sorted[#sorted+1]=name end;table.sort(sorted)
  for _,name in ipairs(sorted) do
    names_q[#names_q+1]=name;captions_q[#captions_q+1]=(prototypes.quality and prototypes.quality[name] and prototypes.quality[name].localised_name) or name
    if state.quality==name then index=#names_q end
  end
  state.qualities,state.methods=names_q,METHODS
  bar.se_quality.items=captions_q;bar.se_quality.selected_index=index
  bar.se_method.selected_index=state.method=="rocket" and 2 or state.method=="cannon" and 3 or 1
end

-- Environment tags and hazards can wrap, so their value sits under the label.
local WIDE_ZONE_ROWS={environment=true,hazards=true}

-- Centre card height for SE zone details plus the top resources table.
local function zone_card_height(rows,resources)
  local h=24+30
  for _,r in ipairs(rows) do h=h+(WIDE_ZONE_ROWS[r.name] and 2 or 1)*ZONE_LINE+2 end
  if #resources>0 then h=h+12+(#resources+1)*(ZONE_LINE+2) end
  return h
end

-- SE's zone details in SE's wording, then the richest resources with their
-- map generation size and richness in place of a stored-items count.
local function zone_card(f,inner,rows,resources)
  local props=f.add{type="flow",name="se_zone",direction="vertical"}
  props.style.vertical_spacing=2
  for _,r in ipairs(rows) do
    local wide=WIDE_ZONE_ROWS[r.name]
    local line=props.add{type="flow",name="se_"..r.name,direction=wide and "vertical" or "horizontal"}
    if wide then line.style.vertical_spacing=0 else line.style.horizontal_spacing=6 end
    -- Plain label colour: grey_label disappears against the shallow frame.
    local key=label(line,r.label,nil,wide and inner or nil)
    if not wide then key.style.maximal_width=inner-90;spacer(line) end
    local value=label(line,r.value,nil,wide and inner or nil)
    value.name="se_value";value.tooltip=r.tooltip
    if wide then value.style.single_line=false
    else value.style.maximal_width=inner-60;value.style.horizontal_align="right" end
  end
  if #resources==0 then return end
  f.add{type="line"}.style.width=inner
  local grid=f.add{type="table",name="se_resources",column_count=3}
  grid.style.horizontal_spacing,grid.style.vertical_spacing=6,2
  local size_w,rich_w=56,64;local name_w=inner-size_w-rich_w-12
  for _,head in ipairs({{{"space-exploration.zonelist-resources-header"},name_w,"left"},
      {{"gui-map-generator.size"},size_w,"right"},{{"gui-map-generator.richness"},rich_w,"right"}}) do
    label(grid,head[1],"bold_label",head[2]).style.horizontal_align=head[3]
  end
  for i,res in ipairs(resources) do
    local tip={"space-exploration.zonelist-resource-bar-tooltip","",res.caption,ZoneInfo.percent(res.frequency),
      ZoneInfo.percent(res.size),ZoneInfo.percent(res.richness)}
    local name=label(grid,res.caption,nil,name_w);name.name="se_resource_"..i;name.tooltip=tip
    local size=label(grid,ZoneInfo.percent(res.size),nil,size_w);size.style.horizontal_align="right";size.tooltip=tip
    local rich=label(grid,ZoneInfo.percent(res.richness),nil,rich_w);rich.style.horizontal_align="right";rich.tooltip=tip
  end
end

local function flow(parent,player,surface,state,width,height,data)
  local graph=parent.se_graph
  if not graph then graph=parent.add{type="flow",name="se_graph",direction="vertical"};graph.style.vertical_spacing=0 end
  local endpoints=state.endpoints or {cannons={},receivers={}}
  local has_cannons=#(endpoints.cannons or {})+#(endpoints.receivers or {})+#(data.unpaired or {})>0
  -- Below the graph: 4 px spacing + the one-line note (20), plus 4 px + the 64 px
  -- cannon panel when shown, so the last panel ends on the body's bottom edge.
  local gh=math.max(220,height-(has_cannons and 92 or 24));graph.style.width,graph.style.height=width,gh
  -- An SE zone lists its Universe Explorer details and richest resources in
  -- the centre card, which grows to fit; the ribbon ports stay on its middle.
  local zone_rows=ZoneInfo.rows(surface)
  local zone_resources=zone_rows and ZoneInfo.resources(surface,5) or {}
  local center_h=zone_rows and math.min(gh-60,math.max(CENTER_HEIGHT,zone_card_height(zone_rows,zone_resources))) or CENTER_HEIGHT
  local center_y=math.max(58,math.floor((gh-center_h)/2))
  local port_center=center_y+center_h/2
  local card_w=math.min(360,math.floor(width*.27))
  local center_w=zone_rows and math.min(300,math.floor(width*.22)) or math.min(240,math.floor(width*.20))
  local cx=math.floor((width-center_w)/2)
  local available=math.max(160,gh-80);local row_count=1
  local grouping=state.group=="items" and "items" or "transport"
  local card_rows={};local slots,top={},{}
  if grouping=="items" then slots,top=item_slots(data.groups) end
  for side,groups in pairs(data.groups or {}) do for _,g in ipairs(groups) do
    card_rows[g]=route_rows(g,side,grouping,slots[side] or {});row_count=math.max(row_count,#card_rows[g])
  end end
  local per_page=math.max(1,math.floor(available/(ROUTE_FIXED+ROUTE_GAP+ROUTE_ROW*row_count)))
  local lists={imports={},exports={}};local max_total=1
  -- Zone values (threat, robot interference, resources) change at runtime, so
  -- the card is rebuilt from their displayed values, not their counts.
  local function flat(value)
    if type(value)~="table" then return tostring(value) end
    local parts={};for i=1,#value do parts[i]=flat(value[i]) end
    return "{"..table.concat(parts,",").."}"
  end
  local zone_parts={}
  for _,r in ipairs(zone_rows or {}) do zone_parts[#zone_parts+1]=r.name..flat(r.label)..flat(r.value)..flat(r.tooltip) end
  for _,r in ipairs(zone_resources) do zone_parts[#zone_parts+1]=r.name..":"..r.size..":"..r.richness end
  local signature={width,gh,state.scope_revision or 0,surface.name,"gui",grouping,table.concat(top,","),
    zone_rows and "zone" or "plain",table.concat(zone_parts,";")}
  local function manifest_signature(items)
    if not items then return "unknown" end
    local parts={"known"};for _,v in ipairs(items) do parts[#parts+1]=v.name..":"..v.quality..":"..v.count end
    return table.concat(parts,",")
  end
  for _,side in ipairs({"imports","exports"}) do
    local groups=(data.groups or {})[side] or {};local pages=math.max(1,math.ceil(#groups/per_page))
    local page=math.max(1,math.min(state[side.."_page"] or 1,pages));state[side.."_page"],state[side.."_pages"]=page,pages
    signature[#signature+1]=side..":"..page..":"..pages..":"..per_page;local total=0
    for i=(page-1)*per_page+1,math.min(#groups,page*per_page) do
      local g=groups[i];local n=0
      for _,m in ipairs(g.methods) do
        signature[#signature+1]=m.method..manifest_signature(m.sent)..manifest_signature(m.received)..manifest_signature(m.sent_observed)
      end
      for _,r in ipairs(card_rows[g]) do n=n+r.ribbon end
      total=total+n;lists[side][#lists[side]+1]={group=g,total=n};signature[#signature+1]=g.id
    end
    max_total=math.max(max_total,total)
  end
  local scale=math.min(available*.55,CENTER_HEIGHT-2*PORT_INSET)/max_total
  local function fits(candidate)
    for _,list in pairs(lists) do
      local h=0
      for _,cell in ipairs(list) do
        h=h+ROUTE_FIXED+ROUTE_GAP
        for _,r in ipairs(card_rows[cell.group]) do h=h+method_height(r.ribbon*candidate) end
      end
      if h>available then return false end
    end
    return true
  end
  if not fits(scale) then
    local low,high=0,scale
    for _=1,20 do local middle=(low+high)/2;if fits(middle) then low=middle else high=middle end end
    scale=low
  end
  local key=table.concat(signature,"|")
  local rebuild=graph.tags.signature~=key
  if rebuild then graph.clear();graph.tags={signature=key} end
  local painter
  if rebuild then
    Canvas.clear(player.index)
    -- Insert below the existing cards and controls during retained refreshes.
    local slot=graph.add{type="flow",name="se_gui_plot",direction="vertical",index=1}
    slot.style.height,slot.style.bottom_margin=gh,-gh
    painter=GuiPlot.begin(slot,width,gh)
  end
  for _,side in ipairs({"imports","exports"}) do
    -- Shared Transfers palette: imports blue, exports orange. Each row's ribbon
    -- on a side takes the next shade, and its card row a stripe of that shade.
    -- Grouped by Items, the colour follows the item instead (grey for the rest).
    local incoming=side=="imports";local direction=incoming and "in" or "out";local shade=0
    local x=incoming and 4 or width-card_w-4;local list=lists[side];local total_h,total_ports=0,0
    for _,cell in ipairs(list) do
      cell.h=ROUTE_FIXED;for _,r in ipairs(card_rows[cell.group]) do cell.h=cell.h+method_height(r.ribbon*scale) end
      total_h=total_h+cell.h+ROUTE_GAP;total_ports=total_ports+cell.total*scale
    end
    local y=math.max(58,(gh-total_h)/2);local py=port_center-total_ports/2
    if rebuild then
      local h=at(graph,x,2,card_w,54);local r=row(h)
      label(r,incoming and Loc("se-imports") or Loc("se-exports"),"heading_2_label");spacer(r)
      action(r,"left_arrow",Loc("se-previous-routes"),{se_logistics="page",side=side,delta=-1}).enabled=state[side.."_page"]>1
      label(r,Loc("se-page",state[side.."_page"],state[side.."_pages"]),"grey_label")
      action(r,"right_arrow",Loc("se-next-routes"),{se_logistics="page",side=side,delta=1}).enabled=state[side.."_page"]<state[side.."_pages"]
      if #list==0 then label(at(graph,x,80,card_w,48),incoming and Loc("se-no-imports") or Loc("se-no-exports"),"grey_label",card_w) end
    end
    for _,cell in ipairs(list) do
      local g=cell.group;local rows
      if rebuild then
        local card=at(graph,x,y,card_w,cell.h).add{type="frame",name="se_route_card",style="inside_deep_frame",direction="vertical"}
        card.style.width,card.style.height,card.style.padding=card_w,cell.h,2
        -- Strip: remote surface and one History action for the whole route.
        local strip=card.add{type="frame",name="heading",style="subheader_frame",direction="horizontal"}
        strip.style.height,strip.style.padding=ROUTE_STRIP,0
        strip.style.left_padding,strip.style.right_padding=8,4
        strip.style.horizontally_stretchable,strip.style.vertical_align=true,"center"
        local name=plain(label(strip,remote_name(g),"subheader_caption_label"))
        name.name,name.tooltip,name.style.maximal_width="route_name",remote_name(g),card_w-4-12-28-8
        spacer(strip)
        action(strip,"search",Loc("se-ui-open-history"),route_tags(g,nil,state,side)).name="route_history"
        rows=card.add{type="table",name="rows",column_count=1,style="ssk_balance_grid",draw_horizontal_lines=true}
        rows.style.horizontal_spacing,rows.style.vertical_spacing=0,0
        rows.style.top_cell_padding,rows.style.bottom_cell_padding=0,0
        rows.style.left_cell_padding,rows.style.right_cell_padding=0,0
        -- Column heading, so the two numbers in each row are labelled once.
        local head=row(rows,"columns");head.style.width,head.style.height=card_w-4,ROUTE_HEAD
        head.style.left_padding,head.style.right_padding,head.style.horizontal_spacing=8,8,6
        label(head,Loc(grouping=="items" and "se-ui-items" or "se-ui-transport"),"grey_label");spacer(head)
        label(head,Loc("se-ui-sent"),"grey_label",SENT_W).style.horizontal_align="right"
        label(head,Loc("se-ui-received"),"grey_label",RECEIVED_W).style.horizontal_align="right"
      end
      local my=y+ROUTE_FIXED-2
      for _,r in ipairs(card_rows[g]) do
        local thickness=r.ribbon*scale;local mh=method_height(thickness)
        local color,stripe_sprite
        if grouping=="items" then color,stripe_sprite=Shades.item_color(r.slot),Shades.item_sprite(r.slot)
        else shade=shade+1;color,stripe_sprite=Shades.color(direction,shade),Shades.sprite(direction,shade) end
        local tags,tip=r.tags,r.tip
        if thickness>0 then
          local a=incoming and x+card_w or cx+center_w;local b=incoming and cx or x
          local sy=my+(mh-thickness)/2;local ya=incoming and sy or py;local yb=incoming and py or sy
          if rebuild then
            painter.curve(a,b,ya,yb,thickness,color)
            painter.rect(incoming and cx or cx+center_w-8,py,8,thickness,color)
            Tooltip.ribbon(graph,{{kind="curve",x=a,y=math.min(ya,yb),w=b-a,h=math.abs(yb-ya)+thickness,ya=ya,yb=yb,t0=thickness,t1=thickness}},tip,tags)
          end
          py=py+thickness
        end
        if rebuild then
          local line=row(rows,r.name);line.tooltip=tip
          local edge=at(graph,incoming and x+card_w-3 or x,my,3,mh)
          local stripe=edge.add{type="sprite",sprite=stripe_sprite,resize_to_sprite=false,ignored_by_interaction=true}
          stripe.style.width,stripe.style.height,stripe.style.stretch_image_to_widget_size=3,mh,true
          line.style.width,line.style.height,line.style.horizontal_spacing=card_w-4,mh,6
          line.style.left_padding,line.style.right_padding=8,8
          local icon=r.icon or r.item and "item/"..r.item
          if icon and helpers.is_valid_sprite_path(icon) then
            local e
            if r.item then
              -- A slot-style button can show the item's quality badge.
              e=line.add{type="sprite-button",sprite=icon,style="transparent_slot",ignored_by_interaction=true}
              if r.quality and r.quality~="normal" then e.quality=r.quality end
              e.style.padding=0
            else
              e=line.add{type="sprite",sprite=icon,resize_to_sprite=false,ignored_by_interaction=true}
              e.style.stretch_image_to_widget_size=true
            end
            e.style.width,e.style.height=20,20
          end
          local name=plain(label(line,r.caption,r.style));name.style.maximal_width=card_w-4-16-26-SENT_W-RECEIVED_W-18
          spacer(line)
          label(line,number(r.sent),nil,SENT_W).style.horizontal_align="right"
          label(line,number(r.received),nil,RECEIVED_W).style.horizontal_align="right"
        end
        my=my+mh
      end
      y=y+cell.h+ROUTE_GAP
    end
  end
  if rebuild then
    -- Second-level grouping of every route card, centred between the headings.
    local bar=at(graph,cx,2,center_w,54).add{type="flow",name="se_grouping",direction="horizontal"}
    bar.style.width,bar.style.height,bar.style.horizontal_align,bar.style.vertical_align=center_w,28,"center","center"
    bar.add{type="switch",name="se_group",switch_state=grouping=="items" and "right" or "left",allow_none_state=false,
      left_label_caption=Loc("se-ui-transport"),right_label_caption=Loc("se-ui-items"),
      tooltip=Loc("se-ui-group-help"),tags={se_logistics="group"}}
    local holder=at(graph,cx,center_y,center_w,center_h);holder.name="se_center_wrap"
    local f=holder.add{type="frame",name="se_center",style="inside_shallow_frame",direction="vertical"}
    f.style.width,f.style.height,f.style.padding=center_w,center_h,12
    local inner=center_w-24
    plain(label(f,Surfaces.label(surface),"heading_2_label",inner))
    -- No stored-items count or subtitles: the resources take its place.
    if zone_rows then zone_card(f,inner,zone_rows,zone_resources) end
  end
  if not parent.se_flow_note then label(parent,Loc("se-ui-flow-help"),"grey_label",width).name="se_flow_note" end
  -- The ribbon notes live on the flow help line, not in the centre card.
  parent.se_flow_note.tooltip=Loc.join(Loc("se-ui-dispatch-width"),"\n",Loc("se-ui-received-unknown"))
  if has_cannons then
    local panel=parent.se_unpaired or parent.add{type="frame",name="se_unpaired",style="inside_shallow_frame",direction="vertical"}
    panel.clear();panel.style.width,panel.style.padding=width,8
    local h=row(panel);label(h,Loc("se-ui-unpaired-cannons"),"caption_label");spacer(h)
    action(h,"search",Loc("se-ui-open-history"),{se_logistics="history",method="cannon",unpaired=true})
    label(panel,Loc("se-ui-cannon-evidence",state.cannon_shots or 0,#(endpoints.cannons or {}),#(endpoints.receivers or {})),"grey_label",width-24).tooltip=Loc("se-ui-cannon-unknown")
    if endpoints.truncated then label(panel,Loc("se-ui-endpoints-truncated"),"grey_label") end
  elseif parent.se_unpaired then parent.se_unpaired.destroy() end
end

function UI.render(content,player,surface,period,state,width,height)
  if not (surface and surface.valid) then content.clear();return end
  if state.scope_surface~=surface or state.scope_force~=player.force then
    state.scope_revision=(state.scope_revision or 0)+1
    state.scope_surface,state.scope_force=surface,player.force
    state.history={axis=state.history and state.history.axis};state.route=nil
    state.imports_page,state.exports_page=1,1;state.endpoints=nil
  end
  if state.period~=period then
    state.history=state.history or {}
    state.history.bucket,state.history.page,state.history.expanded=nil,nil,nil
    state.period=period
  end
  state.view=state.view or "flow";state.history=state.history or {}
  if not state.endpoints or state.rescan_endpoints then state.endpoints=Cannons.discover(surface,player.force);state.rescan_endpoints=nil end
  local base=Data.query(player.force,surface,game.tick,period,{timing="either",_skip_groups=true})
  state.cannon_shots=#(base.unpaired or {})
  local materials=choices(base,player,surface,state)
  if not state.material and state.view=="items" then state.material=materials[1] end
  local panel=content.ssk_se_logistics
  if not panel or panel.tags.version~=VERSION or panel.tags.width~=width or panel.tags.height~=height then panel=build(content,width,height) end
  panel.se_tabs.selected_tab_index=state.view=="items" and 2 or state.view=="history" and 3 or 1
  local frame=panel.se_tabs["se_"..state.view]
  if state.view=="items" then item_controls((frame.toolbar or frame.viewport.toolbar).controls,base,materials,state) end
  local filters={timing="departure"}
  if state.view=="items" then filters={method=state.method,quality=state.quality~="all" and state.quality or nil,timing="either"} end
  if state.view=="history" and not state.history.return_view then
    state.history.material,state.history.quality,state.history.method=nil,nil,nil
    state.history.route,state.history.direction=nil,nil
  end
  if state.view=="history" then filters={material=state.history.material,quality=state.history.quality,method=state.history.method,route=state.history.route,direction=state.history.direction,timing="either"} end
  local data=Data.narrow(base,filters)
  local coverage=(data.coverage or {})[filters.method=="cannon" and "cannon" or "rocket"] or 0
  local status=panel.heading.se_coverage
  status.caption=data.truncated and Loc("se-history-incomplete") or Loc("ui-recorded",Sampler.duration(coverage),Sampler.duration(period))
  status.tooltip=Tooltip.lines({status.caption,Loc("se-recording-help")})
  data.receipt_coverage=false
  data.sent_coverage=filters.method=="rocket" and not data.truncated and (data.seconds or 0)>0
    and ((data.coverage or {}).rocket or 0)>=data.seconds
  local body=frame.viewport.body
  local size=body.tags
  local w,h=size.width,size.height
  if state.view=="history" then Entities.render(body,player,surface,period,state,w,h,data,state.endpoints)
  elseif state.view=="items" then Items.fill(body,player,surface,period,state,w,h,data,state.endpoints)
  else flow(body,player,surface,state,w,h,data) end
  return (base.coverage or {}).rocket
end
function UI.on_selection(e,state)
  local t=e.element.tags or {}
  if t.se_logistics=="tabs" then
    state.view=VIEWS[e.element.selected_tab_index] or "flow"
    if state.view=="history" then state.history={axis=state.history and state.history.axis} end
    return true
  end
  local f=state.view=="history" and state.history or state
  if t.se_logistics=="material" then f.material=(state.materials or {})[e.element.selected_index] or nil
  elseif t.se_logistics=="quality" then f.quality=(state.qualities or {})[e.element.selected_index] or nil
  elseif t.se_logistics=="method" then f.method=METHODS[e.element.selected_index] or nil
  else return false end
  state.imports_page,state.exports_page=1,1
  if state.view=="history" then f.bucket,f.page,f.expanded,f.exchange,f.event_page=nil,nil,nil,nil,nil end
  return true
end
function UI.on_click(e,state,close_all)
  if Entities.on_click(e,state) then return true end
  local t=e.element.tags or {};if not t.se_logistics then return false end
  if Panels.on_click(e,state,close_all) then return true end
  if t.se_logistics=="items-select" then
    if state.items_members and state.items_members[t.material] then state.material=t.material end
  elseif t.se_logistics=="items-clear-search" then state.items_search=nil
  elseif t.se_logistics=="history" or t.se_logistics=="route" then
    state.history={route=t.route,direction=t.direction,method=t.method or (state.view=="items" and state.method or nil),
      material=t.material or (state.view=="items" and state.material or nil),
      quality=t.quality or (state.view=="items" and state.quality or nil),return_view=state.view or "flow",
      axis=state.history and state.history.axis}
    if t.unpaired then state.history.material,state.history.quality,state.history.direction,state.history.route=nil,nil,nil,nil end
    state.view="history"
  elseif t.se_logistics=="page" and (t.side=="imports" or t.side=="exports") then
    state[t.side.."_page"]=math.max(1,math.min((state[t.side.."_page"] or 1)+t.delta,state[t.side.."_pages"] or 1))
  elseif t.se_logistics=="surface-jump" then
    local player=game.get_player(e.player_index);local endpoint
    for _,r in ipairs(Data.query(player.force,state.scope_surface,game.tick,state.period or 600,{}).records or {}) do
      for _,candidate in pairs({r.sender,r.receiver}) do if candidate.surface==state.scope_surface and Endpoints.resolve(candidate,player.force) then endpoint=candidate;break end end
      if endpoint then break end
    end
    if endpoint then Endpoints.jump(player,endpoint,close_all) end
  elseif t.se_logistics=="clear" then state.material,state.quality,state.method=nil,nil,nil
  else return false end
  return true
end
function UI.on_switch(e,state)
  local el=e.element
  if not (el and el.valid and el.tags and el.tags.se_logistics=="group") then return false end
  if el.switch_state~="left" and el.switch_state~="right" then return false end
  local grouping=el.switch_state=="right" and "items" or "transport"
  if (state.group or "transport")~=grouping then state.group=grouping;state.imports_page,state.exports_page=1,1 end
  return true
end
function UI.on_checked(e,state) return Items.on_checked(e,state) end
function UI.on_translated(e,state) return Items.on_translated(e,state) or Entities.on_translated(e,state) end
function UI.on_text_changed(e,state)
  if Entities.on_text_changed(e,state) then return true end
  if not (e.element.tags and e.element.tags.se_logistics=="items-search") then return false end
  state.items_search=e.element.text
  return true
end
return UI
