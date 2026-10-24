local Sm,UI,SK,B=TREQ("scripts.sampler"),TREQ("scripts.ui"),TREQ("scripts.sankey_ui"),TREQ("scripts.balance")
local player=game.players[1]
local old_storage,old_nets=storage,game.forces.player.logistic_networks
storage={stock={{tick=0,s={[1]={["item/steel-plate"]=-3}}}}}
Sm.init()
assert(#storage.stock==0,"old availability history must not create a stock trend")
local available=-3
local point={owner={unit_number=777},targeted_items_pickup={{name="steel-plate",quality="normal",count=104}}}
local net={get_contents=function() return {{name="steel-plate",quality="normal",count=available}} end,
  provider_points={point},storage_points={point}}
assert(Sm.network_stock(net)["item/steel-plate"]==101,"stored stock is physical 101, not available -3 or clamped zero")
local mixed={get_contents=function() return {{name="speed-module",quality="normal",count=-6},{name="speed-module",quality="uncommon",count=58}} end,
  provider_points={{owner={unit_number=778},targeted_items_pickup={{name="speed-module",quality="normal",count=8}}}}}
assert(Sm.network_stock(mixed)["item/speed-module"]==60,"reservations and qualities must combine without cancellation")
game.forces.player.logistic_networks={nauvis={net}}
Sm.on_stock(0);available=-5;Sm.on_stock(600)
assert(Sm.stock(1)["item/steel-plate"].count==99 and Sm.stock(1)["item/steel-plate"].per_min==-12,"stock trend must use corrected stored counts")
storage,game.forces.player.logistic_networks=old_storage,old_nets
player.mod_settings["ssk-debug-tabs"]={value=false}
local us=storage.ui[1];us.tab_id="balance";us.bal_filter="all";us.period=600
SK.balance_state(us).focus="fluid/water"
UI.open(player)
local function find(e,pred)
 if pred(e) then return e end
 for _,c in ipairs(e.children) do local x=find(c,pred);if x then return x end end
end
local root=player.gui.screen.ssk_main
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
assert(h and h.ssk_help_tabs,"in-game help must open without replacing the main window")
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
print("USABILITY OK: physical stock, reservation/quality correction, history baseline, controls, help and explicit list refresh")
