-- Entity navigation for surface History. Nil selection means Total.
local Loc=require("scripts.locale")
local Panels=require("scripts.se_transfer_panels")
local N={}
local GROUPS={
  cannon={order=1,title=Loc("history-entities-cannons")},rocket_sender={order=2,title=Loc("history-entities-launch-pads")},
  rocket_receiver={order=3,title=Loc("history-entities-landing-pads")},receiver={order=4,title=Loc("history-entities-receivers")},
  silo={order=5,title=Loc("history-entities-silos")},hub={order=6,title=Loc("history-entities-hubs")},
  landing={order=7,title=Loc("history-entities-cargo-pads")},container={order=8,title=Loc("history-entities-cargo-landings")},
  other={order=9,title=Loc("history-entities-other")}}
local function group(e)
  local kind=e.kind
  if kind=="rocket_sender" then return "rocket_sender" end
  if kind=="rocket_receiver" then return "rocket_receiver" end
  if e.name=="se-delivery-cannon" then return "cannon" end
  if e.name=="se-delivery-cannon-chest" then return "receiver" end
  if e.name=="rocket-silo" then return "silo" end
  if e.name=="space-platform-hub" then return "hub" end
  if e.name=="cargo-landing-pad" then return "landing" end
  if e.name=="cargo-pod-container" then return "container" end
  return "other"
end
function N.key(endpoint,surface,force)
  if not (endpoint and endpoint.unit_number and endpoint.surface==surface and endpoint.force==force) then return nil end
  return tostring(surface.index)..":"..tostring(endpoint.unit_number)
end
function N.matches(record,key,surface,force)
  return N.key(record.sender,surface,force)==key or N.key(record.receiver,surface,force)==key
end
function N.entries(data,surface,force,endpoints,method)
  local map={}
  local function add(e)
    local key=N.key(e,surface,force)
    if not key then return end
    if not map[key] then map[key]={key=key,endpoint=e,group=group(e),count=0,last=nil} end
    return map[key]
  end
  for _,record in ipairs(data.records or {}) do
    local seen={}
    for _,e in pairs({sender=record.sender,receiver=record.receiver}) do
      local entry=add(e)
      if entry and not seen[entry.key] then
        seen[entry.key]=true;entry.count=entry.count+1
        local tick=record.direction=="imports" and record.arrival_tick or record.tick
        tick=tick or record.tick
        entry.last=math.max(entry.last or 0,tick or 0)
      end
    end
  end
  if method~="rocket" and method~="cargo-pod" then
    for _,kind in ipairs({"cannons","receivers"}) do for _,e in ipairs(endpoints and endpoints[kind] or {}) do add(e.endpoint) end end
  end
  local entries={};for _,entry in pairs(map) do entries[#entries+1]=entry end
  table.sort(entries,function(a,b)
    local ag,bg=GROUPS[a.group].order,GROUPS[b.group].order
    if ag~=bg then return ag<bg end
    return a.endpoint.unit_number<b.endpoint.unit_number
  end)
  return entries,map
end
local function title(entry)
  local e=entry.endpoint
  local proto=prototypes.entity and prototypes.entity[e.name]
  return Loc("history-entities-name",proto and proto.localised_name or e.name,tostring(e.unit_number))
end
local function clock(tick)
  if not tick then return "—" end
  local t=math.floor(tick/60)
  return string.format("%02d:%02d:%02d",math.floor(t/3600),math.floor(t/60)%60,t%60)
end
local function label(parent,name,text,width,style,numeric)
  local e=parent.add{type="label",name=name,caption=text,style=style}
  e.style.width,e.style.single_line=width,true
  e.style.horizontal_align=numeric and "right" or "left"
  return e
end
local function grid(parent,name)
  local e=parent.add{type="table",name=name,style="ssk_balance_grid",column_count=4,draw_horizontal_lines=true,draw_vertical_lines=true}
  e.style.horizontal_spacing,e.style.vertical_spacing=0,0
  e.style.left_cell_padding,e.style.right_cell_padding=3,3
  e.style.top_cell_padding,e.style.bottom_cell_padding=5,5
  return e
end
local function favourites(player)
  local us=storage.ui[player.index]
  us.transport_entity_favs=us.transport_entity_favs or {}
  return us.transport_entity_favs
end
-- The sidebar matches the Transfers Items list: a 56 px toolbar strip, then the
-- heading, Total and entity rows in one bordered box inset 12 px that reaches
-- down to the note, so the list area, not bare panel, takes any spare height.
-- A 12 px scrollbar lane and 8 px gutter sit right of the rows. While every row
-- fits, with one to spare, the entity column takes both (wheel scrolling stays
-- on), so the rows meet the box's right edge as they meet its left one.
local LANE,GUTTER,ROW_H,GROUP_H=12,8,34,36
local PAD,STRIP_H,NOTE_H=12,56,44
-- Height left for the rows below the heading (32) and Total (34) rows.
local function rows_space(height) return math.max(80,height-STRIP_H-PAD-NOTE_H-32-34-8) end
local function build(parent,width,height)
  parent.clear()
  local outer=math.max(300,math.min(450,math.floor(width*.32)))
  local root=parent.add{type="flow",name="entity_history",direction="horizontal",tags={width=width,height=height,left=outer,framed=2}}
  root.style.horizontal_spacing,root.style.width,root.style.height=12,width,height
  -- Match Balance's inset list and chart: sibling deep frames share the same
  -- background and border depth, rather than drawing a separate dividing line.
  local sidebar=root.add{type="frame",name="sidebar",style="inside_deep_frame",direction="vertical"}
  sidebar.style.width,sidebar.style.height=outer,height
  sidebar.style.padding=0
  local box_w=outer-2*PAD
  local left=box_w-GUTTER
  -- Same toolbar strip as Balance: 12 px at the sides, 8 px above and below a
  -- 40 px row, controls 8 px apart (frames cannot space their children).
  local strip=sidebar.add{type="frame",name="strip",style="subheader_frame",direction="horizontal"}
  strip.style.horizontally_stretchable,strip.style.height=true,STRIP_H
  strip.style.left_padding,strip.style.right_padding=PAD,PAD
  strip.style.top_padding,strip.style.bottom_padding=8,8
  local bar=strip.add{type="flow",name="controls",direction="horizontal"}
  bar.style.height,bar.style.horizontally_stretchable=40,true
  bar.style.vertical_align,bar.style.horizontal_spacing="center",8
  label(bar,nil,Loc("history-entities-title"),math.max(100,outer-2*PAD-144-28-16),"subheader_caption_label")
  local search=bar.add{type="textfield",name="search",text="",style="search_popup_textfield",tooltip=Loc("history-entities-search"),tags={history_entity_search=true}}
  search.style.width=144
  bar.add{type="sprite-button",style="tool_button",sprite="utility/reset",tooltip=Loc("transport-items-clear-search"),tags={history_entity_clear_search=true}}
  local box=sidebar.add{type="frame",name="box",style="inside_deep_frame",direction="vertical"}
  box.style.width,box.style.height,box.style.padding=box_w,height-STRIP_H-PAD-NOTE_H,0
  box.style.left_margin,box.style.top_margin=PAD,PAD
  local header=box.add{type="frame",name="header",style="ssk_balance_header",direction="vertical"}
  header.style.width,header.style.height=box_w,32
  local heads=grid(header,"columns");heads.style.top_cell_padding,heads.style.bottom_cell_padding=2,2
  label(heads,nil,"",24,"bold_label")
  label(heads,"entity_heading",Loc("history-entities-entity"),left-198,"bold_label")
  label(heads,nil,Loc("history-entities-records"),62,"bold_label",true)
  label(heads,nil,Loc("history-entities-observed"),76,"bold_label",true)
  local total=grid(box,"total")
  local b=total.add{type="sprite-button",style="tool_button",sprite="utility/list_view",tooltip=Loc("history-entities-total-help"),tags={history_entity_total=true}}
  b.style.width,b.style.height=24,24
  label(total,"total_caption",Loc("history-entities-total"),left-198,"bold_label").tags={history_entity_total=true}
  label(total,"count","",62,"bold_label",true)
  label(total,nil,Loc("history-entities-all"),76,"bold_label",true)
  local scroll=box.add{type="scroll-pane",name="scroll",style="naked_scroll_pane",horizontal_scroll_policy="never",vertical_scroll_policy="auto-and-reserve-space"}
  scroll.style.width=box_w
  scroll.style.vertically_stretchable,scroll.style.minimal_height=true,0
  local rows=scroll.add{type="flow",name="rows",direction="vertical"};rows.style.vertical_spacing=0
  -- Up to two lines, centred in a fixed band so one-line text sits mid-band.
  local note=label(sidebar,"note",Loc("history-entities-help"),box_w,"grey_label");note.style.single_line=false
  note.style.left_margin,note.style.top_margin,note.style.height,note.style.vertical_align=PAD,4,40,"center"
  local main=root.add{type="frame",name="main",style="inside_deep_frame",direction="vertical"}
  main.style.width,main.style.height=width-outer-12,height
  main.style.padding=4
  return root
end
function N.render(parent,player,surface,period,state,width,height,data,endpoints,context)
  state.history=state.history or {};local hs=state.history
  local entries,map=N.entries(data,surface,player.force,endpoints,hs.method)
  if not map[hs.entity] then hs.entity=nil end
  hs._entity_keys,hs._entity_groups,hs._entity_counts={},{},{}
  for key,entry in pairs(map) do hs._entity_keys[key]=true;hs._entity_groups[key]=entry.group;hs._entity_counts[key]=entry.count end
  if not hs.entity_names or hs.entity_locale~=player.locale then
    hs.entity_locale=player.locale;hs.entity_names={};hs.entity_requested={};hs.entity_pending={}
  end
  if player.request_translations then
    local names,strings={},{}
    for _,entry in ipairs(entries) do
      local name=entry.endpoint.name
      if not hs.entity_requested[name] then
        hs.entity_requested[name]=true;names[#names+1]=name
        strings[#strings+1]=(prototypes.entity and prototypes.entity[name] or {}).localised_name or name
      end
    end
    if #strings>0 then for i,id in ipairs(player.request_translations(strings)) do hs.entity_pending[id]=names[i] end end
  end
  local favs=favourites(player)
  table.sort(entries,function(a,b)
    local ag,bg=GROUPS[a.group].order,GROUPS[b.group].order
    if ag~=bg then return ag<bg end
    local af,bf=not not favs[a.key],not not favs[b.key]
    if af~=bf then return af end
    return a.endpoint.unit_number<b.endpoint.unit_number
  end)
  local root=parent.entity_history
  if not root or root.tags.framed~=2 or root.tags.width~=width or root.tags.height~=height then root=build(parent,width,height) end
  local sidebar=root.sidebar
  local box,left=sidebar.box,root.tags.left-2*PAD-GUTTER
  local groups,last=0,nil
  for _,entry in ipairs(entries) do if entry.group~=last then groups,last=groups+1,entry.group end end
  -- Estimated from every entry (the search can only shorten the list), so typing
  -- in the search box does not make the columns jump.
  local extra=(#entries+1)*ROW_H+groups*GROUP_H<=rows_space(height) and LANE+GUTTER or 0
  box.scroll.vertical_scroll_policy=extra>0 and "dont-show-but-allow-scrolling" or "auto-and-reserve-space"
  box.header.columns.entity_heading.style.width=left-198+extra
  box.total.total_caption.style.width=left-198+extra
  box.total.children[1].toggled=hs.entity==nil
  box.total.count.caption=tostring(#(data.records or {}))
  if sidebar.strip.controls.search.text~=(hs.entity_search or "") then sidebar.strip.controls.search.text=hs.entity_search or "" end
  local query=(hs.entity_search or ""):lower()
  local shown={}
  for _,entry in ipairs(entries) do
    local e=entry.endpoint
    local translated=hs.entity_names[e.name]
    if query=="" or translated and translated:lower():find(query,1,true) or tostring(e.unit_number):find(query,1,true) or e.name:lower():find(query,1,true)
      or e.name:lower():gsub("%-"," "):find(query,1,true) then shown[#shown+1]=entry end
  end
  local signature={tostring(extra)}
  for _,e in ipairs(shown) do signature[#signature+1]=e.key..":"..tostring(favs[e.key]) end
  signature=table.concat(signature,"|")
  local rows=box.scroll.rows
  if rows.tags.signature~=signature then
    rows.clear();rows.tags={signature=signature}
    local current,table
    for i,entry in ipairs(shown) do
      if current~=entry.group then
        current=entry.group
        local group_header=rows.add{type="frame",style="repeated_subheader_frame",direction="horizontal"}
        group_header.style.width,group_header.style.left_padding=left-LANE+extra,6
        label(group_header,nil,GROUPS[current].title,left-24+extra,"caption_label")
        table=grid(rows,"group_"..current)
      end
      local star=table.add{type="sprite-button",style="tool_button",sprite=favs[entry.key] and "ssk-star" or "ssk-star-off",
        tooltip=Loc(favs[entry.key] and "balance-remove-from-favourites" or "balance-add-to-favourites-always-listed-at-the",title(entry)),tags={history_entity_favourite=entry.key}}
      star.style.width,star.style.height=24,24
      local name=label(table,nil,title(entry),left-198+extra);name.tags={history_entity=entry.key};name.tooltip=title(entry)
      name.style.height=24
      label(table,nil,"",62,nil,true);label(table,nil,"",76,nil,true)
    end
  end
  local offsets={}
  for _,entry in ipairs(shown) do
    local table=rows["group_"..entry.group];local offset=offsets[entry.group] or 0;local cells=table.children
    cells[offset+2].style.font=hs.entity==entry.key and "default-bold" or "default"
    cells[offset+3].caption=tostring(entry.count);cells[offset+4].caption=clock(entry.last)
    offsets[entry.group]=offset+4
  end
  local filtered=data
  if hs.entity then
    filtered={};for k,v in pairs(data) do filtered[k]=v end
    filtered.records={}
    for _,record in ipairs(data.records or {}) do if N.matches(record,hs.entity,surface,player.force) then filtered.records[#filtered.records+1]=record end end
  end
  Panels.history(root.main,player,surface,period,state,width-root.tags.left-20,height-8,filtered)
  if context then
    context.clear()
    label(context,nil,hs.entity and Loc("history-entities-selected",title(map[hs.entity])) or Loc("history-entities-total-help"),width,"caption_label")
  end
end
local function reset(hs)
  hs.bucket,hs.exchange,hs.expanded,hs.page,hs.event_page=nil,nil,nil,1,nil;hs._scroll_reset=true
end
function N.on_click(e,state)
  local t=e.element.tags or {};state.history=state.history or {};local hs=state.history
  if t.history_entity_total then hs.entity=nil;reset(hs)
  elseif t.history_entity then
    if hs._entity_keys and hs._entity_keys[t.history_entity] then
      hs.entity=t.history_entity;reset(hs)
      -- An unmeasured cannon payload cannot satisfy an item-only filter.
      if hs._entity_groups[t.history_entity]=="cannon" and hs._entity_counts[t.history_entity]==0 then hs.material,hs.quality,hs.route=nil,nil,nil end
    end
  elseif t.history_entity_favourite then
    if hs._entity_keys and hs._entity_keys[t.history_entity_favourite] then
      local favs=favourites(game.get_player(e.player_index));favs[t.history_entity_favourite]=not favs[t.history_entity_favourite] or nil
    end
  elseif t.history_entity_clear_search then hs.entity_search=nil
  else return false end
  return true
end
function N.on_text_changed(e,state)
  if not (e.element.tags or {}).history_entity_search then return false end
  state.history=state.history or {};state.history.entity_search=e.element.text
  return true
end
function N.on_translated(e,state)
  local hs=state.history
  local name=hs and hs.entity_pending and hs.entity_pending[e.id]
  if not name then return false end
  hs.entity_pending[e.id]=nil
  if e.translated then hs.entity_names[name]=e.result end
  return true
end
return N
