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
  local jump = button()
  assert(jump.visible and jump.enabled and jump.spec.style == "tool_button"
    and jump.sprite == "utility/go_to_arrow" and jump.tooltip:find("remote view",1,true))
  assert(click(jump) and player.centered_on == a.hub and not UI.is_open(player))
  assert(us.transfers.platform == a.index and us.transfers.view == mode, "Jump lost Transfers selection")
end
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
