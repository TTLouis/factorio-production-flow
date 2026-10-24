local UI=TREQ("scripts.ui")
local player,us=game.players[1],storage.ui[1]
local function find(e,pred)
  if pred(e) then return e end
  for _,c in ipairs(e.children) do local x=find(c,pred); if x then return x end end
end
for _,tab in ipairs({"balance","focus","sankey"}) do
  us.tab_id=tab; us.live=true
  local SK=TREQ("scripts.sankey_ui")
  local fx=tab=="balance" and SK.balance_state(us) or tab=="focus" and SK.focus_state(us) or us
  fx.live=true; fx.focus="item/iron-plate"
  UI.open(player)
  local root=player.gui.screen.ssk_main
  local bar=find(root,function(e) return e.name=="ssk_bar" end)
  local first=bar.children[1]
  UI.refresh(player,true)
  assert(bar.children[1]==first,"live refresh destroys "..tab.." controls")
  local node=find(root,function(e) return e.tags.ssk_sk=="node" end)
  if node then
    local parent=node.parent
    local index
    for i,e in ipairs(parent.children) do if e==node then index=i end end
    UI.on_hover({element=node,player_index=player.index},true)
    UI.refresh(player,true)
    assert(parent.children[index]==node,"hovered node destroyed mid-selection")
    UI.on_hover({element=node,player_index=player.index},false)
    UI.refresh(player,true)
    assert(bar.children[1]==first,"post-hover refresh destroys controls")
  end
end
-- Inspecting a row must not reapply list membership/order after live sampling
-- changes statuses. Rebuilding the table here discards its native scroll state.
local Balance=TREQ("scripts.balance")
local SK=TREQ("scripts.sankey_ui")
us.tab_id="balance"; us.bal_filter="all"; us.bal_sort="priority"
UI.open(player)
local root=player.gui.screen.ssk_main
local list=find(root,function(e) return e.name=="ssk_bal_root" end)
local items=list.ssk_bal_items
local keys=list.tags.visible_keys
local target=find(list,function(e) return e.tags.ssk_ui=="focus_item" and e.tags.key==keys[#keys] end)
local original_rows=Balance.rows
Balance.rows=function(...)
  local rows,seconds=original_rows(...)
  local changed={}
  for i=#rows,2,-1 do
    rows[i].status="ok"
    changed[#changed+1]=rows[i]
  end
  return changed,seconds
end
SK.balance_state(us).live=false
local old_canvas=find(root,function(e) return e.name=="ssk_canvas" end).children[1]
assert(UI.on_click{element=target,player_index=player.index})
assert(find(root,function(e) return e.name=="ssk_bal_root" end)==list,
  "inspecting a row rebuilt the scrolled Balance list")
assert(list.ssk_bal_items==items and target.valid,"selection replaced scrolled click targets")
assert(SK.balance_state(us).focus==target.tags.key,"row selection did not update inspector")
assert(find(root,function(e) return e.name=="ssk_canvas" end).children[1]~=old_canvas,
  "paused inspector must redraw after explicit row selection")
UI.on_click{element=find(root,function(e) return e.tags.ssk_sk=="inputs_more" end),player_index=player.index}
assert(find(root,function(e) return e.name=="ssk_bal_root" end)==list,
  "inspector control rebuilt the scrolled Balance list")
Balance.rows=original_rows
UI.on_click{element=find(root,function(e) return e.tags.ssk_ui=="bal_update" end),player_index=player.index}
assert(find(root,function(e) return e.name=="ssk_bal_root" end)~=list,"Update list must still rebuild rows")
print("SELECTION REFRESH OK: stable controls, scrolled row selection and hovered nodes")
