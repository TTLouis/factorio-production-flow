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
    local old_panel=assert(find(player.gui.screen.ssk_main,"ssk_transfers"))
    old_panel.tags.transfers_layout=7
    UI.refresh(player)
    assert(old_panel.valid==false,"Saved Transfers panel did not migrate to paired placement resets")
  end
  local jump = button()
  assert(jump.visible and jump.enabled and jump.spec.style == "tool_button"
    and jump.sprite == "utility/go_to_arrow" and LOC(jump.tooltip):find("remote view",1,true))
  assert(click(jump) and player.centered_on == a.hub and not UI.is_open(player))
  assert(us.transfers.platform == a.index and us.transfers.view == mode, "Jump lost Transfers selection")
end
-- Time-history targets are reused across refreshes. Each absolute overlay has
-- its own zero-size reset, including after hiding/restoring shorter histories.
local Transfers=TREQ("scripts.transfers")
local original_view=Transfers.platform_view
local bucket_count=3
Transfers.platform_view=function(...)
  local result=original_view(...)
  result.from_tick,result.to_tick=game.tick-180,game.tick
  result.buckets={}
  local function cargo(n)return{pods=n,weight=0,count=n,items={}}end
  for i=1,bucket_count do
    result.buckets[i]={start_tick=game.tick-180+(i-1)*30,end_tick=game.tick-180+i*30,
      loaded=cargo(1),unloaded=cargo(0)}
  end
  return result
end
us.transfers={platform=a.index,view="history"}
UI.open(player)
local first=assert(find(player.gui.screen.ssk_main,"ssk_transfer_bucket_loaded_1"))
local last=assert(find(player.gui.screen.ssk_main,"ssk_transfer_bucket_loaded_3"))
local chart=first.parent
local function aligned_history()
  for _,scale in ipairs({1,1.25,1.5}) do
    local function px(v)local n=(v or 0)*scale;return n<0 and math.ceil(n) or math.floor(n)end
    local cursor=0
    for _,el in ipairs(chart.children) do if el.visible~=false then
      if el.tags.transfer_direction then assert(cursor==0,"Transfer hover targets drift at fractional scale")end
      local s=el.style;cursor=cursor+px(s.top_margin)+px(s.height)+px(s.bottom_margin)
    end end
    assert(cursor==0,"Transfer overlays did not restore the plot origin")
  end
end
aligned_history()
local child_count=#chart.children
UI.refresh(player,true)
assert(first.valid and chart.ssk_transfer_bucket_loaded_1==first and #chart.children==child_count,
  "Refresh duplicated named position resets or replaced reusable hover targets")
aligned_history()
bucket_count=1;UI.refresh(player,true)
local reset=assert(chart["ssk_transfer_position_reset_"..last.name])
assert(not last.visible and not reset.visible,"Hidden target left an active position reset")
aligned_history()
bucket_count=3;UI.refresh(player,true)
assert(last.visible and reset.visible and #chart.children==child_count,"Restored target did not reuse its position reset")
aligned_history()
Transfers.platform_view=original_view
UI.open(player)
assert(click(find(player.gui.screen.ssk_main, "platform_102").pick))
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
print("TRANSFERS UI PASS: remote jump from Flow/History, selection, stale/deleted/foreign targets and empty state")
