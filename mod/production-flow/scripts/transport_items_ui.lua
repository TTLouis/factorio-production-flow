-- Shipment-manifest membership with Balance's native table and History inspector.
local Loc=require("scripts.locale")
local Balance=require("scripts.balance")
local BalanceUI=require("scripts.balance_ui")
local History=require("scripts.history")
local HistoryUI=require("scripts.history_ui")
local I={}
local function number(n)
  if n==nil then return "—" end
  local a=math.abs(n)
  if a>=1000000 then return Loc("balance-m",string.format("%.2f",n/1000000)) end
  if a>=10000 then return Loc("balance-k",string.format("%.1f",n/1000)) end
  if a>=100 then return string.format("%.0f",n) end
  if a>=10 then return string.format("%.1f",n) end
  if a>=1 then return string.format("%.2f",n) end
  if a>0 and a<.001 then return "<0.001" end
  return string.format("%.3f",n)
end
local function empty_in(seconds)
  if not seconds then return "—" end
  return Loc.join("≈ ",seconds>=3600 and Loc("balance-h",string.format("%.1f",seconds/3600))
    or seconds>=60 and Loc("balance-min",string.format("%.0f",seconds/60)) or Loc("balance-s",string.format("%.0f",seconds)))
end
local function label(parent,name,caption,width,style,numeric)
  local e=parent.add{type="label",name=name,caption=caption,style=style}
  e.style.width,e.style.single_line=width,true
  e.style.horizontal_align=numeric and "right" or "left"
  return e
end
local function title(name)
  return Loc.join("[item="..name.."] ",(prototypes.item[name] or {}).localised_name or name)
end
function I.manifests(data,state,endpoints)
  local set={}
  for _,record in ipairs(data.records or {}) do
    if (not state.method or record.method==state.method) and (not state.items_direction or record.direction==state.items_direction) then
      for _,field in ipairs({"sent","received"}) do for _,item in ipairs(record[field] or {}) do
        if item.count>0 and (not state.quality or state.quality=="all" or (item.quality or "normal")==state.quality) then
          local r=set[item.name] or {name=item.name,sent=0,received=0};set[item.name]=r
          if record.direction=="exports" and field=="sent" and record.tick>=data.from_tick and record.tick<=data.to_tick then r.sent=r.sent+item.count end
          if record.direction=="imports" and field=="received" and record.arrival_tick and record.arrival_tick>=data.from_tick and record.arrival_tick<=data.to_tick then
            r.received=r.received+item.count;r.received_known=true
          end
        end
      end end
    end
  end
  if state.method~="rocket" then for _,cannon in ipairs(endpoints and endpoints.cannons or {}) do
    local payload=cannon.declared_payload
    if payload then
      set[payload.name]=set[payload.name] or {name=payload.name,sent=0,received=0,sent_unknown=true}
      set[payload.name].configured=true
      if state.method=="cannon" then set[payload.name].sent_unknown=true end
    end
  end end
  local names={};for name in pairs(set) do names[#names+1]=name end;table.sort(names)
  return names,set
end
local function columns(width)
  local out={{id="fav",caption="",width=24},{id="item",caption=Loc("balance-item-fluid"),width=0},
    {id="sent",caption=Loc("se-ui-sent"),width=64},{id="received",caption=Loc("se-ui-received"),width=76},
    {id="cons",caption=Loc("balance-used-s"),width=64},{id="stock",caption=Loc("balance-stock"),width=64},
    {id="eta",caption=Loc("balance-empty-in"),width=74}}
  local fixed=0;for _,c in ipairs(out) do fixed=fixed+c.width end
  out[2].width=math.max(80,width-fixed-#out*6)
  return out
end
-- The list is a deep panel like the History inspector beside it: a 56 px toolbar
-- strip, then the column heading and rows in their own bordered box inset 12 px,
-- then the note along the bottom. A scrolling list keeps a 12 px scrollbar lane
-- and an 8 px gutter; a list that fits gives both to the item column, so its rows
-- meet the box's right edge as they meet its left one.
local LANE,GUTTER,ROW_H,LAYOUT=12,8,34,4
local PAD,STRIP_H,HEADER_H,NOTE_H,HBAR=12,56,32,36,12
local function dimensions(width)
  local left=math.min(820,math.max(570,math.floor(width*.46)),math.floor(width*.54))
  local box=left-2*PAD
  return left,width-left-12,math.max(550,box-LANE-GUTTER),box
end
-- Visible row height inside the box. The horizontal scrollbar only appears when
-- the minimum column widths exceed the box, so only then is its 12 px reserved.
local function rows_height(width,height)
  local _,_,content,box=dimensions(width)
  local box_h=height-STRIP_H-PAD-NOTE_H
  return box_h-HEADER_H-(content+LANE+GUTTER>box and HBAR or 0),box_h
end
local function grid(parent,name,cols,style)
  -- As in Balance, row shading follows the cells when native horizontal lines drift.
  local t=parent.add{type="table",name=name,style=style,column_count=#cols,
    draw_horizontal_lines=false,draw_vertical_lines=true}
  t.style.horizontal_spacing,t.style.vertical_spacing=0,0
  t.style.left_cell_padding,t.style.right_cell_padding=3,3
  return t
end
local function build(parent,width,height)
  parent.clear()
  -- Preserve the History inspector on smaller windows; the list can scroll horizontally.
  local left_width,right_width,content_width,box_width=dimensions(width)
  local rows_h,box_h=rows_height(width,height)
  local root=parent.add{type="flow",name="transport_items",direction="horizontal",tags={width=width,height=height,layout=LAYOUT}}
  root.style.horizontal_spacing=12
  local left=root.add{type="frame",name="list",style="inside_deep_frame",direction="vertical"}
  left.style.width,left.style.height,left.style.padding=left_width,height,0
  -- Same toolbar strip as Balance: 12 px at the sides, 8 px above and below a
  -- 40 px row, controls 8 px apart (frames cannot space their children).
  local strip=left.add{type="frame",name="strip",style="subheader_frame",direction="horizontal"}
  strip.style.horizontally_stretchable,strip.style.height=true,STRIP_H
  strip.style.left_padding,strip.style.right_padding=PAD,PAD
  strip.style.top_padding,strip.style.bottom_padding=8,8
  local bar=strip.add{type="flow",name="controls",direction="horizontal"}
  bar.style.height,bar.style.horizontally_stretchable=40,true
  bar.style.vertical_align,bar.style.horizontal_spacing="center",8
  label(bar,"title",Loc("transport-items-title"),math.max(80,left_width-2*PAD-168-28-16),"subheader_caption_label")
  local search=bar.add{type="textfield",name="search",text="",style="search_popup_textfield",
    tags={se_logistics="items-search"},tooltip=Loc("material-picker-search-item-and-fluid-names")}
  search.style.width=168
  bar.add{type="sprite-button",style="tool_button",sprite="utility/reset",tooltip=Loc("transport-items-clear-search"),tags={se_logistics="items-clear-search"}}
  -- The heading row and rows share one bordered box, as in Balance.
  local box=left.add{type="frame",name="box",style="inside_deep_frame",direction="vertical"}
  box.style.width,box.style.height,box.style.padding=box_width,box_h,0
  box.style.left_margin,box.style.top_margin=PAD,PAD
  local viewport=box.add{type="scroll-pane",name="viewport",style="naked_scroll_pane",vertical_scroll_policy="never",horizontal_scroll_policy="auto"}
  viewport.style.width,viewport.style.height=box_width,box_h
  local cols=columns(content_width)
  local full=content_width+LANE+GUTTER
  local stack=viewport.add{type="flow",name="stack",direction="vertical"};stack.style.width=full;stack.style.vertical_spacing=0
  local header=stack.add{type="frame",name="header",style="ssk_balance_header",direction="vertical"}
  header.style.width,header.style.height,header.style.bottom_padding=full,HEADER_H,4
  local headings=grid(header,"columns",cols,"ssk_balance_grid");headings.style.top_cell_padding,headings.style.bottom_cell_padding=2,2
  for _,c in ipairs(cols) do label(headings,c.id,c.caption,c.width,"bold_label",c.id~="fav" and c.id~="item") end
  header.add{type="line",name="line",direction="horizontal"}.style.width=full
  local scroll=stack.add{type="scroll-pane",name="rows",style="naked_scroll_pane",horizontal_scroll_policy="never",vertical_scroll_policy="auto-and-reserve-space"}
  scroll.style.width,scroll.style.height=full,rows_h
  local table=grid(scroll,"grid",cols,"ssk_striped_rows")
  table.style.top_cell_padding,table.style.bottom_cell_padding=5,5
  local note=label(left,"note","",left_width-2*PAD,"grey_label");note.style.single_line=false
  note.style.left_margin,note.style.top_margin,note.style.height=PAD,8,20
  local inspector=root.add{type="frame",name="inspector",style="inside_deep_frame",direction="vertical"}
  inspector.style.width,inspector.style.height,inspector.style.padding=right_width,height,0
  return root,cols,right_width
end
function I.fill(parent,player,surface,period,state,width,height,data,endpoints)
  local root=parent.transport_items
  local cols,right_width
  if not root or root.tags.width~=width or root.tags.height~=height or root.tags.layout~=LAYOUT then root,cols,right_width=build(parent,width,height)
  else local _,right,content=dimensions(width);cols=columns(content);right_width=right end
  local names,totals=I.manifests(data,state,endpoints)
  local root_us=storage.ui[player.index]
  local favs=BalanceUI.favourites(root_us).items
  local member={};for _,name in ipairs(names) do member[name]=true end
  if not member[state.material] then state.material=names[1] end
  state.items_members=member
  if state.items_locale~=player.locale or not state.items_names then
    state.items_locale=player.locale;state.items_names={};state.items_pending={};state.items_requested={}
  end
  if player.request_translations then
    local strings,keys={},{}
    for _,name in ipairs(names) do if not state.items_requested[name] then
      state.items_requested[name]=true;keys[#keys+1]=name;strings[#strings+1]=(prototypes.item[name] or {}).localised_name or name
    end end
    if #strings>0 then for i,id in ipairs(player.request_translations(strings)) do state.items_pending[id]=keys[i] end end
  end
  table.sort(names,function(a,b)
    local af,bf=not not favs["item/"..a],not not favs["item/"..b]
    if af~=bf then return af end;return a<b
  end)
  local query=(state.items_search or ""):lower()
  local visible={}
  for _,name in ipairs(names) do
    local translated=state.items_names and state.items_names[name] or name:gsub("%-"," ")
    if query=="" or translated:lower():find(query,1,true) or name:lower():find(query,1,true) then visible[#visible+1]=name end
  end
  local trusted=player.force==game.forces.player and (not state.quality or state.quality=="all")
  local rows,seconds,stock,known={},0,{},false
  if trusted then rows,seconds,stock,known=Balance.rows(surface.index,period) end
  local by_key={};for _,r in ipairs(rows) do by_key[r.key]=r end
  -- While every row fits (with one to spare) the item column takes the scrollbar
  -- lane. The rows still scroll with the mouse wheel, so a low estimate never clips.
  local stack=root.list.box.viewport.stack
  local extra=(#visible+1)*ROW_H<=rows_height(width,height) and LANE+GUTTER or 0
  stack.rows.vertical_scroll_policy=extra>0 and "dont-show-but-allow-scrolling" or "auto-and-reserve-space"
  stack.header.columns.item.style.width=cols[2].width+extra
  local cells_grid=stack.rows.grid
  local signature=extra..":"..table.concat(visible,"|")..":"..table.concat((function()local f={};for _,n in ipairs(visible) do f[#f+1]=favs["item/"..n] and "1" or "0" end;return f end)(),"")
  if cells_grid.tags.signature~=signature then
    cells_grid.clear();cells_grid.tags={signature=signature}
    for _,name in ipairs(visible) do
      for _,c in ipairs(cols) do
        local cell
        if c.id=="fav" then
          cell=cells_grid.add{type="sprite-button",style="tool_button",sprite=favs["item/"..name] and "ssk-star" or "ssk-star-off",
            tags={ssk_ui="bal_fav",key="item/"..name},tooltip=Loc(favs["item/"..name] and "balance-remove-from-favourites" or "balance-add-to-favourites-always-listed-at-the",title(name))}
          cell.style.width,cell.style.height=24,24
        else cell=label(cells_grid,nil,"",c.width+(c.id=="item" and extra or 0),nil,c.id~="item") end
      end
    end
  end
  local children=cells_grid.children
  for i,name in ipairs(visible) do
    local row=by_key["item/"..name]
    local count=trusted and (row and row.stock or stock["item/"..name] and stock["item/"..name].count or known and 0) or nil
    local consumption=trusted and seconds>0 and (row and row.cons or 0) or nil
    local values={item=title(name),sent=totals[name].sent_unknown and "—" or number(totals[name].sent),received=totals[name].received_known and number(totals[name].received) or "—",
      stock=number(count),cons=number(consumption),eta=empty_in(row and row.eta)}
    for j,c in ipairs(cols) do
      local cell=children[(i-1)*#cols+j]
      if c.id~="fav" then
        cell.caption=values[c.id];cell.style.font=c.id=="item" and name==state.material and "default-bold" or "default"
        cell.style.height=24
        if c.id=="item" then cell.tags={se_logistics="items-select",material=name};cell.tooltip=totals[name].configured and Loc.join(title(name),"\n",Loc("transport-items-recipe")) or title(name)
        elseif c.id=="sent" or c.id=="received" then
          cell.tags={se_logistics="history",direction=c.id=="sent" and "exports" or "imports",material=name,quality=state.quality,method=state.method}
          cell.tooltip=Loc("transport-items-observed")
        else
          cell.tooltip=not trusted and Loc("se-ui-stock-scope-unavailable") or Loc(c.id=="cons" and "balance-measured-consumption-per-second-on-the-selected"
            or c.id=="eta" and "balance-estimated-time-until-chest-stock-is-empty" or "balance-physical-contents-of-ordinary-and-logistic-chests")
        end
      end
    end
  end
  root.list.strip.controls.title.caption=Loc("transport-items-count",#visible,#names)
  if root.list.strip.controls.search.text~=(state.items_search or "") then root.list.strip.controls.search.text=state.items_search or "" end
  root.list.note.caption=#names==0 and Loc("se-ui-no-records") or Loc("transport-items-observed")
  state.items_history=state.items_history or {}
  local context=state.items_history
  context.sidx,context.period,context.bal_height=surface.index,period,height
  local key=state.material and "item/"..state.material
  local h=key and trusted and History.build(surface.index,period,key) or {start_tick=data.from_tick,end_tick=data.to_tick,seconds=0,points={},usage_keys={},stock={},stock_supported=true}
  local receipts={}
  for _,r in ipairs(data.records or {}) do if r.direction=="imports" and r.arrival_tick then
    local count=0;for _,item in ipairs(r.received or {}) do if item.name==state.material then count=count+item.count end end
    if count>0 then receipts[#receipts+1]={tick=r.arrival_tick,count=count} end
  end end
  HistoryUI.fill(player,root.inspector,context,key,right_width,height,56,{history=h,receipts=receipts})
  local header=root.inspector.ssk_history_toolbar.ssk_history_controls.ssk_history_header
  header.ssk_history_usage.tags={se_logistics="items-usage"};header.ssk_history_from_zero.tags={se_logistics="items-zero"}
  header.ssk_material_heading.ssk_material_slot.tags={};header.ssk_material_heading.ssk_material_slot.enabled=false
  if not trusted then
    root.inspector.ssk_history_scroll.ssk_history_body.ssk_history_stock_state.caption=Loc("se-ui-stock-scope-unavailable")
  end
end
function I.on_checked(e,state)
  local t=e.element.tags or {}
  if t.se_logistics~="items-usage" and t.se_logistics~="items-zero" then return false end
  state.items_history=state.items_history or {}
  state.items_history[t.se_logistics=="items-usage" and "bal_usage_breakdown" or "bal_history_from_zero"]=e.element.state
  return true
end
function I.on_translated(e,state)
  local name=state.items_pending and state.items_pending[e.id]
  if not name then return false end
  state.items_pending[e.id]=nil
  if e.translated then state.items_names[name]=e.result end
  return true
end
return I
