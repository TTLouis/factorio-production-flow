local Sm,UI,SK,B=TREQ("scripts.sampler"),TREQ("scripts.ui"),TREQ("scripts.sankey_ui"),TREQ("scripts.balance")
local player=game.players[1]
player.mod_settings["ssk-debug-tabs"]={value=false}
local us=storage.ui[1];us.tab_id="balance";us.bal_filter="all";us.period=600
SK.balance_state(us).focus="fluid/water"
UI.open(player)
local function find(e,pred)
 if pred(e) then return e end
 for _,c in ipairs(e.children) do local x=find(c,pred);if x then return x end end
end
local root=player.gui.screen.ssk_main
UI.on_click({element=find(root,function(e)return e.tags.ssk_sk=="chart_settings" end),player_index=1})
local live=find(root,function(e)return e.tags.ssk_sk=="live" end)
assert(live.caption=="Auto-update chart","update control must name its scope")
local period=find(root,function(e)return e.tags.ssk_ui=="period" end)
assert(period.items[1]:find("Recent"),"short averaging period must not reuse Live")
local uses=find(root,function(e)return e.tags.ssk_column=="uses" end)
assert(type(uses.caption)=="table" and uses.caption[2]:find("consumed"),"Uses must identify selected-material consumption")
local saved_rates=Sm.rates
Sm.rates=function(...)local rates=saved_rates(...);return rates,42 end
UI.refresh(player,true)
assert(root.ssk_window_bar.ssk_history.visible and root.ssk_window_bar.ssk_history.caption:find("42 / 600"),"warm-up must show available history")
Sm.rates=saved_rates
local help=find(root,function(e)return e.tags.ssk_ui=="help" end)
assert(help.type=="sprite-button" and help.sprite=="utility/questionmark","Help must use the built-in question-mark frame action icon")
assert(not find(root,function(e)return e.tags.ssk_ui=="export" or e.tags.ssk_sk=="f_renderer" end),"normal menus must exclude developer controls")
UI.on_click({element=help,player_index=1})
local h=player.gui.screen.ssk_help
assert(h and h.ssk_help_inner.ssk_help_tabs,"in-game help must open without replacing the main window")
UI.refresh(player,true)
assert(player.gui.screen.ssk_help==h and player.gui.screen.ssk_main==root,"updates must leave help open")
UI.on_closed({element=root,player_index=1})
assert(not player.gui.screen.ssk_help and player.gui.screen.ssk_main==root,"Escape must close help before the main window")
UI.on_click({element=help,player_index=1});h=player.gui.screen.ssk_help
local close=find(h,function(e)return e.tags.ssk_ui=="help_close" end)
UI.on_click({element=close,player_index=1})
assert(not player.gui.screen.ssk_help and player.opened==root,"closing help must return to the chart")
local fx=SK.balance_state(us);local focus=fx.focus
local list=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root
local update=find(root,function(e)return e.tags.ssk_ui=="bal_update" end)
UI.on_click({element=update,player_index=1})
assert(root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root~=list and fx.focus==focus,"Update list must reapply membership without changing inspected material")
assert(B.STATUS.starved.label=="Low activity" and B.STATUS.limited.label=="Possible supply limit","activity alerts must avoid claiming a confirmed cause")
print("USABILITY OK: physical stock, controls, help and explicit list refresh")
