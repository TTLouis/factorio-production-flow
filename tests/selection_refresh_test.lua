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
print("SELECTION REFRESH OK: stable controls, rows and hovered nodes")
