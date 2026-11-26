local UI = TREQ("scripts.ui")
local player, us = game.players[1], storage.ui[1]
local force = player.force
local saved_tab, saved_platforms, saved_transfers, saved_center = us.tab_id, force.platforms, us.transfers, player.centered_on
local function find(e, name)
  if e.name == name then return e end
  for _, child in ipairs(e.children) do local hit = find(child, name); if hit then return hit end end
end
local function button()
  return assert(find(player.gui.screen.ssk_main, "ssk_transfer_jump"))
end
local function click(el) return UI.on_click{element=el, player_index=player.index} end
local function switch(value)
  local axis=assert(find(player.gui.screen.ssk_main,"axis"))
  axis.switch_state=value
  return UI.on_switch{element=axis,player_index=player.index}
end
local a = {valid=true, index=101, name="Alpha", surface=player.surface}
local b = {valid=true, index=102, name="Beta", surface=player.surface}
a.hub = {valid=true, force=force}
b.hub = {valid=true, force=force}
force.platforms = {a,b}
us.tab_id, us.transfers = "transfers", {platform=a.index}
for _, mode in ipairs({"flow", "history"}) do
  us.transfers.view = mode
  UI.open(player)
  if mode=="history" then
    local axis=assert(find(player.gui.screen.ssk_main,"axis"))
    local old_panel=assert(find(player.gui.screen.ssk_main,"ssk_transfers"))
    old_panel.tags.transfers_layout=7;axis.destroy()
    UI.refresh(player)
    axis=assert(find(player.gui.screen.ssk_main,"axis"))
    assert(old_panel.valid==false,"Saved pre-toggle UI was not migrated")
    assert(axis.spec.type=="switch" and axis.spec.allow_none_state==false,"Two-way modes must use the vanilla switch")
    assert(switch("right") and us.transfers.axis=="events" and axis.switch_state=="right")
    local heading=axis.parent;local before_toggle=true;local paging=0
    local log_header=assert(find(player.gui.screen.ssk_main,"log_headers"))
    assert(heading.spec.style=="subheader_frame" and heading.style.height==38
      and log_header.spec.style=="repeated_subheader_frame" and log_header.style.height==32)
    for _,control in ipairs(heading.children) do
      if control==axis then before_toggle=false end
      if control.tags.transfer_exchange_page then assert(before_toggle,"Event pages must precede the axis switch");paging=paging+1 end
    end
    assert(paging==2)
    assert(switch("left") and us.transfers.axis=="time" and axis.switch_state=="left")
  end
  local jump = button()
  assert(jump.visible and jump.enabled and jump.spec.style == "tool_button"
    and jump.sprite == "utility/map" and LOC(jump.tooltip):find("remote view",1,true))
  assert(click(jump) and player.centered_on == a.hub and not UI.is_open(player))
  assert(us.transfers.platform == a.index and us.transfers.view == mode, "Jump lost Transfers selection")
end
UI.open(player)
local sidebar=assert(find(player.gui.screen.ssk_main,"sidebar"))
local split=sidebar.parent
local tabs=split.tab_row.ssk_transfer_tabs
assert(not split.divider and #split.children==2, "Only the panel borders should separate the platform list and details")
for _, body in ipairs({tabs.ssk_transfer_flow,tabs.ssk_transfer_history}) do
  assert(body.spec.style==sidebar.spec.style
    and sidebar.style.width+split.style.horizontal_spacing+body.style.width==split.parent.style.width,
    "Flow and History must fill the space next to the platform list")
end
local box=sidebar.platform_scroll
local list=box.ssk_transfer_platforms
assert(not sidebar.box and sidebar.heading.spec.style=="subheader_frame" and box.spec.style=="naked_scroll_pane"
  and list.spec.type=="table" and list.spec.column_count==2,"Platforms need a title strip over unboxed rows")
assert(not box.style.left_margin and not box.style.top_margin and box.style.width==sidebar.style.width
  and box.style.height==sidebar.style.height-sidebar.heading.style.height,
  "The platform rows must fill the panel edge to edge, with the scrollbar on its border")
assert(list.children[1]==list.favourite_101 and list.children[2]==list.platform_101,
  "The favourite action must sit in a separate cell to the left of the platform entry")
local node=find(player.gui.screen.ssk_main,"ssk_transfer_platform_node")
if node then
  local stats=node.stats.children
  assert(stats[1]==node.stats.loaded and stats[2]==node.stats.made and stats[3]==node.stats.unloaded
    and stats[4]==node.stats.kept and node.heading.platform_name and node.heading.platform_location,
    "Platform node shows name and location, then loaded, made, unloaded and kept aboard in flow order")
  assert(node.style.height==node.parent.style.height,"Platform node must fill its placed slot")
end
local pick=list.platform_101
assert(pick.spec.type=="button" and pick.spec.style=="list_box_item" and LOC(pick.caption)=="Alpha"
  and pick.style.width+28==list.tags.row_width and pick.style.height==28,
  "Platform rows are full-width list items without the repeated hub icon")
local picked=0
for _,child in ipairs(list.children) do
  if child.tags.transfer_platform then
    assert(child.toggled==(child.tags.transfer_platform==us.transfers.platform),"Only the selected platform is highlighted")
    if child.toggled then picked=picked+1 end
  end
end
assert(picked==1,"Exactly one platform row must be highlighted")
assert(box.vertical_scroll_policy=="dont-show-but-allow-scrolling" and list.tags.row_width==list.tags.full_width,
  "A short platform list must not reserve an empty scrollbar gutter")
-- A short Events page grows towards the left, with newest cargo at the right.
local Transfers=TREQ("scripts.transfers")
local event_count=3
local original_view=Transfers.platform_view
Transfers.platform_view=function(...)
  local result=original_view(...)
  local filters=select(4,...)
  local function cargo(n) return {pods=n,mass=0,unknown_mass=0,items={},count=n} end
  result.exchanges={}
  for i=1,event_count do result.exchanges[i]={key="right:"..i,start_tick=game.tick-180+i*30,end_tick=game.tick-180+i*30,
    loaded=cargo(1),unloaded=cargo(0)} end
  result.exchange=filters.exchange
  return result
end
us.transfers={force=force,period=us.period,platform=a.index,view="history",axis="events"}
UI.open(player)
local first=assert(find(player.gui.screen.ssk_main,"ssk_transfer_bucket_loaded_1"))
local last=assert(find(player.gui.screen.ssk_main,"ssk_transfer_bucket_loaded_3"))
assert(last.style.left_margin+last.style.width==last.parent.style.width-24,"Newest SA event must touch the right plot boundary")
assert(last.style.left_margin-first.style.left_margin==48,"Right alignment changed compact spacing")
assert(click(first) and us.transfers.exchange=="right:1")
local clear_exchange=assert(find(player.gui.screen.ssk_main,"reset_bucket"))
assert(clear_exchange.visible and click(clear_exchange) and us.transfers.exchange==nil,
  "The log needs a visible reset for a selected exchange")
local chart=first.parent
local function aligned_history()
  for _,scale in ipairs({1,1.25,1.5}) do
    local function px(v) local n=(v or 0)*scale;return n<0 and math.ceil(n) or math.floor(n) end
    local cursor=0
    for _,el in ipairs(chart.children) do
      if el.visible~=false then
        local s=el.style
        if el.tags.transfer_direction then
          assert(cursor==0,"History bucket hover regions drift after previous buckets at fractional scale")
        end
        cursor=cursor+px(s.top_margin)+px(s.height)+px(s.bottom_margin)
      end
    end
    assert(cursor==0,"History overlays must restore the plot origin")
  end
end
aligned_history()
local child_count=#chart.children
UI.refresh(player,true)
assert(first.valid and chart.ssk_transfer_bucket_loaded_1==first and #chart.children==child_count,
  "History refresh must retain targets without duplicating position resets")
aligned_history()
event_count=1;UI.refresh(player,true)
assert(not last.visible,"Shorter Events page must hide old bucket targets")
local hidden_reset=assert(chart["ssk_transfer_position_reset_"..last.name])
assert(not hidden_reset.visible,"Hidden bucket must also hide its layout reset")
aligned_history()
event_count=3;UI.refresh(player,true)
assert(last.visible and hidden_reset.visible and #chart.children==child_count,"Restoring events must reuse and show existing resets")
aligned_history()
event_count=200;UI.refresh(player,true)
assert(us.transfers._event_pages>1,"Event fixture must span several pages")
local page_before=us.transfers.event_page
assert(click(find(player.gui.screen.ssk_main,"next_exchanges")))
assert(us.transfers.event_page==page_before+1,"Next must advance exactly one event page")
local chosen_page=us.transfers.event_page
event_count=201;UI.refresh(player,true)
assert(us.transfers.event_page==chosen_page,"New cargo moved the explicitly selected event page")
assert(switch("left"))
assert(switch("right"))
assert(us.transfers.event_page==us.transfers._event_pages,"Entering Events must open its newest page")
Transfers.platform_view=original_view
us.transfers.platform=b.index
UI.open(player)
assert(click(find(player.gui.screen.ssk_main, "platform_102")))
assert(click(button()) and player.centered_on == b.hub, "Jump did not follow the selected platform")

-- Revalidate targets at click time without closing the window or jumping elsewhere.
local function stale(change, restore)
  UI.open(player)
  local jump, previous = button(), player.centered_on
  change()
  assert(click(jump) and UI.is_open(player) and player.centered_on == previous)
  restore()
end
stale(function() b.valid=false end, function() b.valid=true;us.transfers.platform=b.index end)
stale(function() b.hub.valid=false end, function() b.hub.valid=true end)
stale(function() b.hub=nil end, function() b.hub={valid=true,force=force} end)
stale(function() b.hub.force={} end, function() b.hub.force=force end)
stale(function() force.platforms={} end, function() force.platforms={a,b};us.transfers.platform=b.index end)
stale(function() us.transfers.platform=a.index end, function() us.transfers.platform=b.index end)
b.hub.valid=false
UI.open(player)
assert(button().visible and not button().enabled, "Unavailable hub must disable Jump")
force.platforms={}
UI.open(player)
assert(not button().visible and not button().enabled, "No platform must hide Jump")
force.platforms, us.tab_id, us.transfers, player.centered_on = saved_platforms, saved_tab, saved_transfers, saved_center
UI.open(player)
-- Shared ribbon shades: blue in, orange out, green made; four shades per side,
-- appended after the Sankey colours so their indices stay unchanged.
local Shades,Palette=TREQ("shared.ribbon_shades"),TREQ("shared.palette")
assert(Shades.key("in",1)=="ribbon_in_1" and Shades.key("in",5)=="ribbon_in_1" and Shades.key("out",3)=="ribbon_out_3"
  and Shades.key("made",2)=="ribbon_made" and Shades.sprite("out",2)=="ssk-plot-ribbon_out_2","Ribbon shades must cycle per side")
assert(#Palette.colors==16 and Palette.RIBBON==Palette.DIM+16 and Palette.OVERVIEW_DIM>Palette.RIBBON+10
  and Palette.rgb(Palette.RIBBON+1)[3]==math.floor(Shades.color("in",1).b*255+0.5),"Ribbon shades must follow the Sankey palette")
-- SE item colours are exact muted Sankey colours, so night-vision curves reuse
-- the Sankey sprites; iron and copper keep their Sankey blue and orange.
for slot,index in ipairs(Shades.ITEM_SANKEY) do
  local c,rgb=Shades.item_color(slot),Palette.rgb(index)
  assert(math.floor(c.r*255+0.5)==rgb[1] and math.floor(c.g*255+0.5)==rgb[2] and math.floor(c.b*255+0.5)==rgb[3],
    "Item colour "..slot.." must match Sankey colour "..index)
end
local both,out_only,in_only={imports=true,exports=true},{exports=true},{imports=true}
local entries={{key="iron-plate/normal",sides=both},{key="copper-plate/normal",sides=out_only},
  {key="steel-plate/normal",sides=out_only},{key="iron-plate/rare",sides=out_only}}
for i=1,4 do entries[#entries+1]={key="filler-"..i.."/normal",sides=out_only} end
entries[#entries+1]={key="wood/normal",sides=in_only}
entries[#entries+1]={key="coal/normal",sides=in_only}
local slots=Shades.assign_items(entries)
assert(slots["iron-plate/normal"]==1 and slots["copper-plate/normal"]==2 and slots["steel-plate/normal"]==3
  and slots["iron-plate/rare"]==4 and Shades.item_sprite(nil)=="ssk-plot-ribbon_item_other","Item colour slots")
-- With all eight colours taken on exports, import-only items reuse colours
-- that are still unique on the import side and never iron's.
assert(slots["wood/normal"] and slots["coal/normal"] and slots["wood/normal"]~=slots["coal/normal"]
  and slots["wood/normal"]~=1 and slots["coal/normal"]~=1,"Per-side colours must stay unique")
print("TRANSFERS UI PASS: remote jump from Flow/History, selection, stale/deleted/foreign targets and empty state")
