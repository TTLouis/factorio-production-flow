-- Injected into an isolated copy only. Never included in release packages.
local T = {}
local mode = require("scripts.save_test_mode")
local SK = require("scripts.sankey_ui")
local Model = require("scripts.model")
local View = require("scripts.view")
local Diag = require("scripts.diag")
local ChestStock=require("scripts.chest_stock")
local start, step, capture = nil, 0, nil
local captures, skipped, products, usage_labels = {}, {}, {}, {}

local cases = {
  {name="nauvis-balance", surface="nauvis", tab="balance"},
  {name="nauvis-overview", surface="nauvis", tab="sankey", view="overview"},
  {name="nauvis-items", surface="nauvis", tab="sankey", view="detail"},
  {name="nauvis-inputs", surface="nauvis", tab="balance", focus="item/iron-plate", depth=3},
  {name="vulcanus-overview", surface="vulcanus", tab="sankey", view="overview"},
  {name="fulgora-overview", surface="fulgora", tab="sankey", view="overview"},
  {name="gleba-overview", surface="gleba", tab="sankey", view="overview"},
  {name="aquilo-overview", surface="aquilo", tab="sankey", view="overview"},
  {name="nauvis-focus", surface="nauvis", tab="focus", focus="item/electronic-circuit"},
  {name="platform-overview", surface="platform-6", tab="sankey", view="overview"},
  {name="nauvis-advanced", surface="nauvis", tab="sankey", view="overview", advanced=true},
  {name="nauvis-sprites", surface="nauvis", tab="sankey", view="overview", renderer="sprites"},
}
if mode == "balance" then
  cases = {
    {name="balance-iron", surface="nauvis", tab="balance", focus="item/iron-plate", depth=3},
    {name="balance-circuit", surface="nauvis", tab="balance", focus="item/electronic-circuit", depth=2},
    {name="balance-steel", surface="nauvis", tab="balance", focus="item/steel-plate", depth=1},
    {name="balance-condensation", surface="vulcanus", tab="balance", focus="fluid/water", depth=1},
    {name="balance-steam", surface="vulcanus", tab="balance", focus="fluid/steam", depth=1},
    {name="balance-acid", surface="vulcanus", tab="balance", focus="fluid/sulfuric-acid", depth=1},
    {name="balance-molten-iron", surface="vulcanus", tab="balance", focus="fluid/molten-iron", depth=1},
    {name="balance-lubricant", surface="vulcanus", tab="balance", focus="fluid/lubricant", depth=1},
    {name="balance-petroleum", surface="nauvis", tab="balance", focus="fluid/petroleum-gas", depth=1},
    {name="balance-ice-melting", surface="platform-6", tab="balance", focus="fluid/water", depth=1},
    {name="balance-condensation-pinned", surface="vulcanus", tab="balance", focus="fluid/water", depth=1, pin="fluid/steam#input"},
    {name="balance-condensation-proportional", surface="vulcanus", tab="balance", focus="fluid/water", depth=1, heights="linear"},
  }
end
if mode == "full" then
  cases={
    {name="full-nauvis",surface="nauvis",tab="sankey",view="overview"},
    {name="full-vulcanus",surface="vulcanus",tab="sankey",view="overview"},
    {name="full-fulgora",surface="fulgora",tab="sankey",view="overview"},
    {name="full-gleba",surface="gleba",tab="sankey",view="overview"},
    {name="full-aquilo",surface="aquilo",tab="sankey",view="overview"},
    {name="full-platform",surface="platform-6",tab="sankey",view="overview"},
    {name="full-platform-copper",surface="platform-6",tab="sankey",view="detail",preset="roots:item/copper-plate"},
    {name="full-vulcanus-copper",surface="vulcanus",tab="sankey",view="detail",preset="roots:item/copper-plate"},
    {name="full-nauvis-oil",surface="nauvis",tab="sankey",view="detail",preset="super:oil"},
    {name="full-vulcanus-oil",surface="vulcanus",tab="sankey",view="detail",preset="super:oil"},
    {name="full-nauvis-items",surface="nauvis",tab="sankey",view="detail"},
    {name="full-oil-pinned",surface="nauvis",tab="sankey",view="detail",preset="super:oil",pin="fluid/petroleum-gas"},
    {name="full-nauvis-sprites",surface="nauvis",tab="sankey",view="overview",renderer="sprites"},
    {name="full-nauvis-proportional",surface="nauvis",tab="sankey",view="overview",heights="linear"},
    {name="focus-circuit",surface="nauvis",tab="focus",focus="item/electronic-circuit"},
    {name="focus-condensation",surface="vulcanus",tab="focus",focus="fluid/water"},
    {name="focus-petroleum",surface="nauvis",tab="focus",focus="fluid/petroleum-gas"},
    {name="full-balance-regression",surface="vulcanus",tab="balance",focus="fluid/water",depth=1},
    {name="balance-iron-usage",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1},
    {name="balance-steam-usage",surface="vulcanus",tab="balance",focus="fluid/steam",depth=1},
  }
end

if mode == "scroll" then
  cases={
    {name="balance-scroll-top",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1},
    {name="balance-scroll-bottom",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,bottom=true},
    {name="balance-scroll-details",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,bottom=true,details=true},
    {name="balance-groups-top",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,groups=true},
    {name="balance-groups-details",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,groups=true,details=true},
    {name="balance-scroll-groups",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,bottom=true,groups=true},
    {name="balance-beta-water",surface="vulcanus",tab="balance",focus="fluid/water",depth=1},
    {name="balance-favourites",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,groups=true,
      favs={items={["item/steel-plate"]=true,["item/stone"]=true},groups={["plates"]=true}}},
  }
end

if mode=="names" then
  cases={
    {name="full-platform-copper",surface="platform-6",tab="sankey",view="detail",preset="roots:item/copper-plate"},
    {name="full-vulcanus-copper",surface="vulcanus",tab="sankey",view="detail",preset="roots:item/copper-plate"},
  }
end

if mode=="audit" then
  cases={{name="stock-audit",surface="nauvis",tab="balance",focus="item/steel-plate",depth=1}}
end

local audit_fixture
local function audit_stock(Sampler)
  local C=ChestStock
  local surface=game.create_surface("chest-stock-audit",{width=64,height=64,default_enable_all_autoplace_controls=false})
  surface.request_to_generate_chunks({0,0},1);surface.force_generate_chunk_requests()
  local tiles={};for y=-10,10 do for x=-10,10 do tiles[#tiles+1]={name="refined-concrete",position={x,y}} end end
  surface.set_tiles(tiles)
  local expected=0
  for i,name in ipairs({"wooden-chest","iron-chest","steel-chest","requester-chest","buffer-chest","storage-chest","passive-provider-chest","active-provider-chest"}) do
    local chest=surface.create_entity{name=name,position={-8+2*i,0},force="player"}
    assert(chest and chest.insert{name="steel-plate",count=i,quality="normal"}==i)
    assert(chest.insert{name="steel-plate",count=2*i,quality="rare"}==2*i)
    C.add(chest);expected=expected+3*i
  end
  C.rescan() -- Include the entire fixture in a fresh scan.
  audit_fixture={surface=surface.index,expected=expected}
end
local function finish_audit(Sampler)
  local measured=Sampler.stock(audit_fixture.surface)["item/steel-plate"]
  assert(measured and measured.count==audit_fixture.expected,"Native chest stock fixture mismatch")
  local report={tick=game.tick,fixture=audit_fixture,measured=measured,types={},surfaces={},sampler=Sampler.stock_status()}
  for _,surface in pairs(game.surfaces) do
    local n=0
    for _,chest in pairs(surface.find_entities_filtered{type={"container","logistic-container"},force="player"}) do
      report.types[chest.name]=(report.types[chest.name] or 0)+1;n=n+1
    end
    if n>0 then report.surfaces[surface.name]={chests=n,stock=Sampler.stock(surface.index)} end
  end
  helpers.write_file("save-test/stock-audit.json",helpers.table_to_json(report),false)
  log("STOCK AUDIT all eight chest types and mixed qualities: "..measured.count.." items")
end

if mode=="ux" then
  cases={
    {name="ux-water",surface="vulcanus",tab="balance",focus="fluid/water",depth=1},
    {name="ux-stock",surface="nauvis",tab="balance",focus="item/steel-plate",depth=1,details=true},
    {name="ux-copper",surface="vulcanus",tab="balance",focus="item/copper-plate",depth=1},
    {name="ux-steam",surface="vulcanus",tab="balance",focus="fluid/steam",depth=1},
    {name="ux-list-update",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,update_list=true},
    {name="ux-help-basics",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,help_tab=1},
    {name="ux-help-stock",surface="nauvis",tab="balance",focus="item/steel-plate",depth=1,help_tab=2},
    {name="ux-help-alerts",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1,help_tab=3},
    {name="ux-recent",surface="vulcanus",tab="balance",focus="fluid/steam",depth=1,recent=true},
  }
elseif mode=="warmup" then
  cases={{name="ux-warmup",surface="nauvis",tab="balance",focus="item/iron-plate",depth=1}}
end
local function find_ui(el,action)
  if el.tags and el.tags.ssk_ui==action then return el end
  for _,child in pairs(el.children) do local x=find_ui(child,action);if x then return x end end
end

local function find_node(element)
  if element.tags and element.tags.ssk_sk == "node" then return element end
  for _, child in pairs(element.children) do
    local found = find_node(child)
    if found then return found end
  end
end

local function find_action(element, action, key)
  if element.tags and element.tags.ssk_sk==action and (not key or element.tags.key==key) then return element end
  for _, child in pairs(element.children) do
    local found=find_action(child,action,key); if found then return found end
  end
end

local function find_scope(element)
  if element.tags and element.tags.ssk_ui=="surface" then return element end
  for _,child in pairs(element.children) do local found=find_scope(child); if found then return found end end
end

local function verify_usage(element, root, result)
  local key=element.tags and element.tags.ssk_rate
  if key and key:match("#use$") then
    local node=find_action(root,"node",key)
    assert(node.tooltip[9]==" consumed", "Uses tooltip lost selected material")
    assert(element.caption==node.tooltip[6], "Uses label still shows consumer output")
    result[key]=element.caption
  end
  for _,child in pairs(element.children) do verify_usage(child,root,result) end
end

function T.tick(UI, Sampler)
  start = start or game.tick
  local elapsed = game.tick - start
  if mode == "history" then
    if elapsed == 0 then
      game.speed = 64
      for _, p in pairs(game.players) do UI.close(p) end
      log("SANKEY SAVE START tick="..game.tick)
    end
    if elapsed % 3600 == 0 then log("SANKEY SAVE progress="..elapsed.."/36060") end
    if elapsed == 36060 then
      local report = {tick=game.tick, elapsed_ticks=elapsed, surfaces={}, mods=script.active_mods}
      for _, s in pairs(game.surfaces) do
        if s.name ~= "ssk-canvas" then
          local rates, secs = Sampler.rates(s.index, 600)
          assert(secs == 600, s.name.." history is "..secs.." seconds")
          local m = Model.build(s.index, 600)
          local n = 0; for _ in pairs(rates.recipes) do n=n+1 end
          report.surfaces[#report.surfaces+1]={name=s.name, seconds=secs, recipes=n, edges=#m.edges}
        end
      end
      helpers.write_file("save-test/history.json", helpers.table_to_json(report), false)
      game.auto_save("sankey-warmed")
      log("SANKEY SAVE HISTORY OK")
    end
    return
  end
  if elapsed == 0 then
    if mode=="audit" then audit_stock(Sampler) end
    game.speed = 1
    local _, seconds = Sampler.rates(game.surfaces.nauvis.index, 600)
    if mode~="warmup" then assert(seconds == 600, "Ten-minute history did not survive save/reload")
    else assert(seconds<600,"Warm-up case must use a fresh installation's history") end
    Sampler.on_stock(game.tick)
    log("SANKEY SAVE RELOAD HISTORY OK")
  end
  if not Sampler.stock_known(game.surfaces.nauvis.index) then return end
  if mode=="audit" and not Sampler.stock_known(audit_fixture.surface) then return end
  if elapsed % 60 ~= 0 then return end
  local player = game.connected_players[1]
  assert(player, "Graphical test has no connected player")
  if capture then
    assert(player.gui.screen.ssk_main, "Missing native GUI")
    if player.gui.screen.ssk_help then player.gui.screen.ssk_help.bring_to_front()
    else player.gui.screen.ssk_main.bring_to_front() end
    if mode=="scroll" and cases[step].bottom then
      -- Live sampling can reorder rows between setup and capture. Exercise the
      -- current list after that refresh, immediately before engine rendering.
      local root=player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root
      local sections=root.ssk_bal_list.ssk_bal_items.children
      local table=sections[#sections].ssk_bal_table
      local rows=table.children
      root.ssk_bal_list.ssk_bal_items.scroll_to_element(rows[#rows-table.column_count+1],"in-view")
    end
    local usage={}
    verify_usage(player.gui.screen.ssk_main,player.gui.screen.ssk_main,usage)
    if next(usage) then usage_labels[capture]=usage end
    if mode=="audit" then finish_audit(Sampler) end
    local node = find_node(player.gui.screen.ssk_main)
    if node then
      assert(node.tooltip ~= nil, "Node has no tooltip")
      assert(UI.on_hover({element=node, player_index=player.index}, true))
      assert(UI.on_hover({element=node, player_index=player.index}, false))
    end
    -- The hidden native window can inherit the desktop cursor position. Clear
    -- tooltip properties only after assertions so that incidental hover popups
    -- do not cover the review captures. The next case reconstructs the GUI.
    local function suppress_tooltips(el)
      el.tooltip=nil
      for _,child in pairs(el.children) do suppress_tooltips(child) end
    end
    suppress_tooltips(player.gui.screen.ssk_main)
    game.take_screenshot{player=player, path="save-test/"..capture..".png",
      resolution={1920,1080}, show_gui=true, force_render=true}
    log("SANKEY SAVE captured="..capture)
    captures[#captures+1] = capture
    capture = nil
    return
  end
  step = step+1
  local c = cases[step]
  if not c then
    if step == #cases+1 then
      Diag.export(player, "save-test")
      helpers.write_file("save-test/gui.json", helpers.table_to_json({captures=captures, skipped=skipped, products=products, usage_labels=usage_labels}), false)
      log("SANKEY SAVE GUI OK")
    end
    return
  end
  if not game.surfaces[c.surface] then
    log("SANKEY SAVE skipped absent="..c.surface)
    skipped[#skipped+1]=c.name
    return
  end
  UI.open(player)
  local us = storage.ui[player.index]
  assert(us.period == 600, "10m is not the initial default")
  us.surface, us.tab_id, us.view = c.surface, c.tab, c.view or "overview"
  us.live, us.advanced = false, c.advanced or false
  us.renderer = c.renderer or "poly"
  if mode=="scroll" or mode=="ux" or mode=="warmup" then
    us.bal_filter="all"; us.bal_details=c.details or false; us.bal_sort=c.groups and "groups" or "priority"; us.bal_group=nil
    us.bal_favs=c.favs or nil
  end
  if (mode=="full" or mode=="names") then
    us.preset=c.preset or "all"; us.sel=nil; us.layout_snapshot=nil; us.auto_rank=nil
    us.show_labels=true; us.heights=c.heights or "sqrt"; us.color_mode="destination"
    us.layout="clean"; us.tier_mode="depth"; us.tier_lo=nil; us.tier_hi=nil
  end
  if c.tab == "balance" and c.focus then
    local fx=SK.balance_state(us); fx.focus=c.focus; fx.input_depth=c.depth; fx.show_labels=true; fx.live=false
    fx.heights=c.heights or "sqrt"; fx.pinned=nil; fx.color_mode="destination"
    local rates, seconds=Sampler.rates(game.surfaces[c.surface].index,600)
    local producers={}
    for _,rn in ipairs(storage.graph.nodes[c.focus].producers) do
      if rates.recipes[rn] and rates.recipes[rn].cps>0 then producers[rn]=rates.recipes[rn].cps end
    end
    products[c.name]={surface=c.surface,focus=c.focus,seconds=seconds,producers=producers}
    if c.name=="balance-condensation" then assert(producers["steam-condensation"], "No measured steam condensation") end
  elseif c.tab == "focus" then
    local fx=SK.focus_state(us); fx.focus=c.focus; fx.live=false
    if (mode=="full" or mode=="names") then fx.show_labels=true; fx.focus_steps=2; fx.layout_snapshot=nil; fx.auto_rank=nil end
  end
  UI.open(player)
  assert(us.sidx==game.surfaces[c.surface].index,"Wrong rendered surface")
  if c.name=="full-platform-copper" or c.name=="full-vulcanus-copper" then
    local preset_picker=find_action(player.gui.screen.ssk_main,"preset")
    assert(us.preset_ids[preset_picker.selected_index]==us.preset,"Preset picker does not identify the displayed copper chain")
    local L=View.build(player,us,us.canvas_w,us.canvas_h)
    assert(L.nodes["item/copper-plate"] and L.nodes["fluid/molten-copper"],"plain copper chain lost its material names")
    for _,n in pairs(L.nodes) do assert(n.kind~="group","plain copper chain still has a category node") end
  end
  assert(us.surface_names[find_scope(player.gui.screen.ssk_main).selected_index]==c.surface,"Surface picker does not identify rendered surface")
  if mode=="balance" or mode=="scroll" or mode=="ux" or mode=="warmup" or ((mode=="full" or mode=="names") and c.tab~="focus") then
    for _,action in ipairs({"center_selection","zoom_fit"}) do
      local button=find_action(player.gui.screen.ssk_main,action)
      assert(button, "Missing Balance action "..action)
      UI.on_click({player_index=player.index,element=button})
    end
    if c.pin then
      local target=find_action(player.gui.screen.ssk_main,"node",c.pin)
      assert(target,"Missing pin target")
      UI.on_click({player_index=player.index,element=target,shift=true})
      assert((c.tab=="balance" and SK.balance_state(us).pinned or us.sel)==c.pin,"Native pin action failed")
      local center=find_action(player.gui.screen.ssk_main,"center_selection")
      UI.on_click({player_index=player.index,element=center})
    end
  end
  if mode=="scroll" then
    local left=player.gui.screen.ssk_main.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table
    local root=left.ssk_bal_root
    assert(left.type=="flow" and root.ssk_bal_list.ssk_bal_items.type=="scroll-pane")
    assert(root.ssk_bal_summary and root.ssk_bal_context and root.ssk_bal_footer.ssk_bal_count)
    if c.bottom then
      local sections=root.ssk_bal_list.ssk_bal_items.children
      local table=sections[#sections].ssk_bal_table
      local rows=table.children
      root.ssk_bal_list.ssk_bal_items.scroll_to_element(rows[#rows-table.column_count+1],"in-view")
    end
  end
  -- Native GUI identity check: a live refresh must retain the controls used by
  -- open selectors, and a hovered node must survive until the pointer leaves.
  local root=player.gui.screen.ssk_main
  local function find_named(el,name)
    if el.name==name then return el end
    for _,child in pairs(el.children) do local x=find_named(child,name); if x then return x end end
  end
  local bar=find_named(root,"ssk_bar")
  local control=bar.children[1]
  local fx=c.tab=="balance" and SK.balance_state(us) or c.tab=="focus" and SK.focus_state(us) or us
  local was_live=fx.live; fx.live=true
  UI.refresh(player,true)
  assert(control.valid and bar.children[1]==control,"Live refresh destroyed selector controls")
  local node=find_node(root)
  if node then
    UI.on_hover({element=node,player_index=player.index},true)
    UI.refresh(player,true)
    assert(node.valid,"Live refresh destroyed hovered selection")
    UI.on_hover({element=node,player_index=player.index},false)
  end
  fx.live=was_live

  if mode=="ux" or mode=="warmup" then
    local help_button=find_ui(root,"help")
    assert(help_button.type=="sprite-button" and help_button.sprite=="utility/questionmark","Help must use built-in icon")
    assert(not find_ui(root,"export") and not find_action(root,"f_renderer"),"Normal menus expose development tools")
    if c.name=="ux-stock" then
      local making=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_focus.ssk_bar.ssk_producers
      assert(making.tags.ssk_recipes[1]=="steel-plate","Main producing recipe must precede recycling")
    end
    if c.recent then
      local period=find_ui(root,"period");period.selected_index=1
      UI.on_selection({player_index=player.index,element=period})
      assert(us.period==0,"Recent period action failed")
    end
    if c.update_list then
      local old=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root
      UI.on_click({player_index=player.index,element=find_ui(root,"bal_update")})
      assert(old.valid==false and SK.balance_state(us).focus==c.focus,"Update list interrupted inspected material")
    end
    if c.help_tab then
      UI.on_click({player_index=player.index,element=find_ui(root,"help")})
      assert(player.gui.screen.ssk_help,"Help action did not open")
      player.gui.screen.ssk_help.ssk_help_inner.ssk_help_tabs.selected_tab_index=c.help_tab
    end
    if c.name=="ux-copper" then
      local making=root.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_focus.ssk_bar.ssk_producers
      local found=false;for _,name in pairs(making.tags.ssk_recipes) do if name=="casting-copper" then found=true end end
      assert(found,"Copper inspector must identify its recorded casting recipe")
    end
    if mode=="warmup" then
      assert(root.ssk_window_bar.ssk_history.visible,"Fresh-install history indicator missing")
      assert(settings.global["ssk-auto-export-minutes"].value==0,"Fresh installs must not export automatically")
    end
  end
  capture = c.name
end
return T
