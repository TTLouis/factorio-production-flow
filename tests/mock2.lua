-- run from the mod folder:  cd mod/production-flow && lua5.2 ../../tests/mock2.lua
TESTDIR = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = "./?.lua;" .. package.path
-- ---------- mock GUI ----------
local Elem = {}
local RESERVED = {}
for w in ("name caption value style visible text state tabs children children_names parent type index gui player_index tooltip sprite tags location direction elem_value items selected_index enabled selected_tab_index badge_text drag_target auto_center number position surface zoom column_count resize_to_sprite clicked_sprite hovered_sprite elem_type horizontal_scroll_policy vertical_scroll_policy entity anchor"):gmatch("%S+") do RESERVED[w] = true end
LABELS = 0
local function new_elem(spec, parent)
  local e = { children = {}, style = {}, valid = true, tags = spec.tags or {}, name = spec.name, type = spec.type,
              parent = parent, spec = spec, state = spec.state, selected_tab_index = 1 }
  for k, v in pairs(spec) do if e[k] == nil then e[k] = v end end
  setmetatable(e, Elem)
  e.add = function(sp) assert(sp.type, "no type")
    if sp.name then assert(not RESERVED[sp.name], "reserved GUI name: " .. sp.name) end
    if sp.type == "label" then LABELS = LABELS + 1 end local c = new_elem(sp, e); table.insert(e.children, c); return c end
  e.clear = function() for _, c in ipairs(e.children) do c.valid = false end; e.children = {} end
  e.scroll_to_element = function(target) assert(target.valid); e.last_scroll_target=target end
  e.destroy = function() e.valid = false
    if e.parent then for i, c in ipairs(e.parent.children) do if c == e then table.remove(e.parent.children, i) break end end end end
  e.add_tab = function() end
  return e
end
Elem.__index = function(t, k)
  for _, c in ipairs(rawget(t, "children")) do if c.name == k and c.valid then return c end end
  return nil
end
function Elem.add(self, spec) assert(spec.type, "no type"); local c = new_elem(spec, self); table.insert(self.children, c); return c end
function Elem.clear(self) for _, c in ipairs(self.children) do c.valid = false end; self.children = {} end
function Elem.destroy(self) self.valid = false
  if self.parent then for i, c in ipairs(self.parent.children) do if c == self then table.remove(self.parent.children, i) break end end end end
function Elem.add_tab(self, t, c) end
local function root() return new_elem({ type = "root" }) end

-- ---------- mock prototypes ----------
local function R(name, ings, prods, cat, sub, energy)
  local ii, pp = {}, {}
  for _, x in ipairs(ings) do ii[#ii+1] = { type = x[3] or "item", name = x[1], amount = x[2] } end
  for _, x in ipairs(prods) do local p = { type = x[3] or "item", name = x[1], amount = x[2] }
    for k, v in pairs(x.extra or {}) do p[k] = v end; pp[#pp+1] = p end
  return name, { name = name, enabled = ENABLED[name] or false, ingredients = ii, products = pp, category = cat or "crafting",
                 subgroup = { name = sub or "x" }, energy = energy or 1, hidden = false }
end
ENABLED = { ["iron-plate"] = true, ["copper-plate"] = true, ["iron-gear-wheel"] = true, ["iron-gear-wheel-2"] = true, ["copper-cable"] = true, ["electronic-circuit"] = true, ["automation-science-pack"] = true, ["iron-gear-wheel-recycling"] = true }
local recipes = {}
local function add(n, p) recipes[n] = p end
add(R("iron-plate", {{"iron-ore",1}}, {{"iron-plate",1}}, "smelting", nil, 3.2))
add(R("copper-plate", {{"copper-ore",1}}, {{"copper-plate",1}}, "smelting", nil, 3.2))
add(R("iron-gear-wheel", {{"iron-plate",2}}, {{"iron-gear-wheel",1}}))
add(R("copper-cable", {{"copper-plate",1}}, {{"copper-cable",2}}))
add(R("electronic-circuit", {{"iron-plate",1},{"copper-cable",3}}, {{"electronic-circuit",1}}))
add(R("kovarex", {{"uranium-235",40},{"uranium-238",5}}, {{"uranium-235",41, extra={ignored_by_productivity=40}},{"uranium-238",2}}, "centrifuging", nil, 60))
add(R("uranium-processing", {{"uranium-ore",10}}, {{"uranium-235",1,extra={probability=0.007}},{"uranium-238",1,extra={probability=0.993}}}, "centrifuging", nil, 12))
add(R("iron-gear-wheel-recycling", {{"iron-gear-wheel",1}}, {{"iron-plate",0.5}}, "recycling"))
add(R("water-barrel", {{"water",50,"fluid"},{"barrel",1}}, {{"water-barrel",1}}, "crafting", "fill-barrel"))
add(R("empty-water-barrel", {{"water-barrel",1}}, {{"water",50,"fluid"},{"barrel",1}}, "crafting", "empty-barrel"))
add(R("automation-science-pack", {{"copper-plate",1},{"iron-gear-wheel",1}}, {{"automation-science-pack",1}}, "crafting", nil, 5))
add(R("logistic-science-pack", {{"inserter",1},{"transport-belt",1}}, {{"logistic-science-pack",1}}, "crafting", nil, 6))
add(R("inserter", {{"electronic-circuit",1},{"iron-gear-wheel",1},{"iron-plate",1}}, {{"inserter",1}}))
add(R("transport-belt", {{"iron-gear-wheel",1},{"iron-plate",1}}, {{"transport-belt",2}}))
add(R("iron-gear-wheel-2", {{"iron-plate",2}}, {{"iron-gear-wheel",1}}))
add(R("advanced-oil-processing", {{"crude-oil",100,"fluid"},{"water",50,"fluid"}}, {{"heavy-oil",25,"fluid"},{"light-oil",45,"fluid"},{"petroleum-gas",55,"fluid"}}, "oil-processing", nil, 5))
add(R("plastic-bar", {{"petroleum-gas",20,"fluid"},{"coal",1}}, {{"plastic-bar",2}}, "chemistry", nil, 1))
local sub = { name = "x" }
prototypes = { recipe = recipes,
  item = setmetatable({}, { __index = function(_, k) return { name = k, subgroup = sub, group = { name = "g" } } end }),
  fluid = setmetatable({}, { __index = function(_, k) return { name = k, subgroup = { name = "fluid" } } end }),
  technology = {
    ["logistics"] = { research_unit_ingredients = { { name = "automation-science-pack" } }, prerequisites = {},
                      effects = { { type = "unlock-recipe", recipe = "logistic-science-pack" }, { type = "unlock-recipe", recipe = "inserter" }, { type = "unlock-recipe", recipe = "transport-belt" } } },
    ["oil-processing"] = { research_unit_ingredients = { { name = "automation-science-pack" }, { name = "logistic-science-pack" } }, prerequisites = {},
                      effects = { { type = "unlock-recipe", recipe = "advanced-oil-processing" }, { type = "unlock-recipe", recipe = "plastic-bar" } } },
    ["kovarex"] = { research_unit_ingredients = {}, prerequisites = { ["oil-processing"] = true },
                      effects = { { type = "unlock-recipe", recipe = "kovarex" }, { type = "unlock-recipe", recipe = "uranium-processing" } } },
  },
  get_entity_filtered = function() return { lab = { lab_inputs = { "automation-science-pack", "logistic-science-pack" } } } end }

-- ---------- mock world ----------
local tick = 0
local machines = {}
MOCK_CHESTS = {}
local function M(recipe, speed, prod, surface)
  local e = { valid = true, type = (recipe:find("plate") and "furnace" or "assembling-machine"),
              unit_number = #machines + 1, surface = surface, force = FORCE, products_finished = 0,
              crafting_speed = speed, productivity_bonus = prod, _r = recipe, name = "am" }
  e.get_recipe = function() return { name = e._r } end
  machines[#machines+1] = e; return e
end
local nauvis = { index = 1, name = "nauvis" }
nauvis.find_entities_filtered = function(filter)
  local t, allowed = {}, {}
  if type(filter.type)=="table" then for _,name in ipairs(filter.type) do allowed[name]=true end
  else allowed[filter.type]=true end
  for _,list in ipairs({machines,MOCK_CHESTS}) do for _,e in ipairs(list) do
    if e.valid and e.surface==nauvis and allowed[e.type] then t[#t+1]=e end
  end end
  return t
end
M("iron-plate", 2, 0, nauvis); M("iron-plate", 2, 0, nauvis); M("copper-plate", 2, 0, nauvis)
M("copper-cable", 1, 0, nauvis); M("electronic-circuit", 1, 0.1, nauvis); M("iron-gear-wheel", 1, 0, nauvis)
M("kovarex", 1, 0, nauvis); M("uranium-processing", 1, 0, nauvis); M("iron-gear-wheel-recycling", 1, 0, nauvis)
M("iron-plate", 2, 0, nauvis); M("iron-plate", 2, 0, nauvis); M("iron-plate", 2, 0, nauvis)
M("automation-science-pack", 1, 0, nauvis); M("logistic-science-pack", 1, 0, nauvis); M("inserter", 1, 0, nauvis)
M("transport-belt", 1, 0, nauvis); M("iron-gear-wheel-2", 1, 0, nauvis); M("iron-gear-wheel-2", 1, 0, nauvis)
M("advanced-oil-processing", 1, 0, nauvis); M("plastic-bar", 1, 0.1, nauvis)
FSTATS = { input_counts = { ["crude-oil"] = 0 }, output_counts = {} }
local stats_in, stats_out = { ["iron-plate"] = 0, ["iron-ore"] = 0 }, { ["iron-ore"] = 0, ["iron-plate"] = 0 }
local fstats = { input_counts = stats_in, output_counts = stats_out }
local player = { index = 1, mod_settings = { ["ssk-min-ribbon-px"] = { value = 6 }, ["ssk-fluid-scale"] = { value = 0.001 }, ["ssk-debug-tabs"] = { value = true } }, surface = nauvis, display_resolution = { width = 3440, height = 1440 }, display_scale = 1,
                 gui = { screen = root(), top = root(), left = root() }, print = print }
FORCE = { logistic_networks = { nauvis = { { get_contents = function() return { { name = "iron-plate", count = math.max(0, 5000 - game.tick / 10), quality = "normal" }, { name = "electronic-circuit", count = 200 + game.tick / 50, quality = "normal" } } end } } }, get_item_production_statistics = function() return fstats end,
                get_fluid_production_statistics = function() return FSTATS end,
                recipes = setmetatable({}, { __index = function() return { productivity_bonus = 0 } end }) }
game = { tick = 0, surfaces = setmetatable({ nauvis }, { __index = function(t, k) if k == "nauvis" then return rawget(t, 1) end end }), players = { player }, connected_players = { player },
         forces = { player = FORCE }, get_player = function() return player end,
         create_random_generator = function(seed) local s = seed
           return function(a, b) s = (s * 1103515245 + 12345) % 2147483648; local f = s / 2147483648
             if a then return a + math.floor(f * (b - a + 1)) end return f end end }
settings = { global = { ["ssk-entities-per-tick"] = { value = 3 }, ["ssk-window-seconds"] = { value = 60 }, ["ssk-auto-export-minutes"] = { value = 5 } } }
WRITES = {}
local function tojson(v)
  local t = type(v)
  if t == "table" then
    if #v > 0 or next(v) == nil then local a = {} for _, x in ipairs(v) do a[#a+1] = tojson(x) end return "[" .. table.concat(a, ",") .. "]" end
    local a = {} for k, x in pairs(v) do a[#a+1] = string.format("%q", tostring(k)) .. ":" .. tojson(x) end return "{" .. table.concat(a, ",") .. "}"
  elseif t == "string" then return string.format("%q", v) elseif t == "nil" then return "null" else return tostring(v) end
end
helpers = { is_valid_sprite_path = function() return true end, table_to_json = tojson,
            write_file = function(n, d, append, pi) WRITES[n] = (append and (WRITES[n] or "") or "") .. d end }
storage = {}
package.loaded["mod-gui"] = { button_style = "mod_gui_button", get_button_flow = function(p) return p.gui.top end }
local handlers, nth = {}, {}
defines = { inventory={chest=1}, events = setmetatable({}, { __index = function(_, k) return k end }) }
script = { active_mods = { ["production-flow"] = "0.0.6", base = "2.0.77", ["space-age"] = "2.0.77" }, on_init = function(f) handlers.init = f end, on_configuration_changed = function(f) handlers.cc = f end,
           on_event = function(id, f) handlers[id] = f end, on_nth_tick = function(n, f) nth[n] = f end }
commands = { add_command = function(n, h, f) handlers["cmd_" .. n] = f end }

dofile(TESTDIR .. "/render_mock.lua")
dofile("control.lua")
local real_require = require
require = function(name) error("Require can't be used outside of control.lua parsing (" .. name .. ")", 2) end
TREQ = function(name) return package.loaded[name] or real_require(name) end
MOCK_CHESTS[1]={valid=true,type="container",unit_number=800001,surface=nauvis,force=FORCE,
  get_inventory=function() return {valid=true,get_contents=function() return {
    {name="iron-plate",count=math.max(0,5000-game.tick/10),quality="normal"},
    {name="electronic-circuit",count=200+game.tick/50,quality="normal"}} end} end}
handlers.init()
assert(player.gui.top.ssk_toggle, "toolbar button missing")
print("graph:", storage.graph.n_nodes, storage.graph.n_recipes, storage.graph.n_reversing, "tracked:", #storage.mlist)

-- simulate 5 minutes: machines craft at speed/energy per second
local acc = {}
for t = 1, 60 * 300 do
  game.tick = t
  for _, m in ipairs(machines) do
    local rate = m.crafting_speed / recipes[m._r].energy / 60
    acc[m] = (acc[m] or 0) + rate
    local whole = math.floor(acc[m]); m.products_finished = m.products_finished + whole; acc[m] = acc[m] - whole
    if whole > 0 and m.valid then
      local rp = recipes[m._r]
      for _, p in ipairs(rp.products) do local T = p.type == "fluid" and FSTATS or fstats
        T.input_counts[p.name] = (T.input_counts[p.name] or 0) + whole * p.amount * (p.probability or 1) * (1 + m.productivity_bonus) end
      for _, i in ipairs(rp.ingredients) do local T = i.type == "fluid" and FSTATS or fstats
        T.output_counts[i.name] = (T.output_counts[i.name] or 0) + whole * i.amount end
    end
  end
  -- stats: iron ore mined 1.5/s, iron-plate produced 1.25/s consumed 1.0/s
  stats_in["iron-ore"] = stats_in["iron-ore"] + 4/60
  stats_in["copper-ore"] = (stats_in["copper-ore"] or 0) + 0.7/60
  FSTATS.input_counts["crude-oil"] = FSTATS.input_counts["crude-oil"] + 20/60
  stats_out["automation-science-pack"] = (stats_out["automation-science-pack"] or 0) + 0.15/60
  handlers.on_tick({ tick = t })
  if t % 60 == 0 then nth[60]({ tick = t }) end
  if t % 300 == 0 then nth[300]({ tick = t }) end
  if t % 600 == 0 then nth[600]({ tick = t }) end
  if t == 100 then machines[6].valid = false end   -- removed gear machine
end
print("tracked after removal:", #storage.mlist, "cycle ticks:", storage.cycle.last)

local Model = TREQ("scripts.model")
local m = Model.build(1)
print("window s:", m.seconds)
for r, x in pairs(m.rates.recipes) do print(string.format("  %-28s %.4f cps  prod %.2f", r, x.cps, x.prod)) end
for _, v in ipairs(m.verts) do print(string.format("  T%d %-32s comp %d", m.vertices[v].tier, v, m.vertices[v].comp)) end
for i, s in ipairs(m.sccs) do print("  SCC", i, table.concat(s, ", ")) end
local r = m.residuals["item/iron-plate"]
print(string.format("iron-plate: prod %.3f measIn %.3f otherSrc %.3f | cons %.3f measOut %.3f otherSink %.3f",
  r.prod, r.meas_in, r.other_src, r.cons, r.meas_out, r.other_sink))

-- exercise the UI: open, every tab, lookup, checkbox, render test, close
local UI = TREQ("scripts.ui")
handlers.on_gui_click({ element = player.gui.top.ssk_toggle, player_index = 1 })
local win = player.gui.screen.ssk_main; assert(win, "window not open")
assert(storage.ui[1].tab_id == "balance", "balance should be the default tab")
assert(storage.ui[1].period == 600, "10 minutes should be the default period")
for _, id in ipairs({ "balance", "focus", "sankey", "graph", "sampler", "model", "render" }) do
  storage.ui[1].tab_id = id; local before = LABELS; UI.refresh(player)
  if id == "balance" then
    assert(win.ssk_inner.ssk_tabs.content_balance.ssk_balance_split.ssk_balance_table.ssk_bal_root, "balance content missing")
  else
    assert(LABELS > before, "tab " .. id .. " rendered nothing")
  end
end
storage.ui[1].lookup = { type = "item", name = "iron-plate" }; storage.ui[1].tab_id = "graph"; UI.refresh(player)
storage.ui[1].tab_id = "model"; UI.refresh(player)
-- observation periods
local Sampler = TREQ("scripts.sampler")
local live = Sampler.rates(1, 0)
for _, per in ipairs({ 600, 3600, 36000 }) do
  local r, secs = Sampler.rates(1, per)
  local a, b = live.recipes["iron-plate"].cps, r.recipes["iron-plate"] and r.recipes["iron-plate"].cps or 0
  print(string.format("period %5d: %.0f s of history, iron-plate %.4f cps (live %.4f)", per, secs, b, a))
  assert(secs > 250 and secs <= 300, "period history length")
  assert(math.abs(a - b) / a < 0.05, "period rate differs from live")
end
storage.ui[1].period = 3600; storage.ui[1].tab_id = "balance"; UI.refresh(player)
handlers.on_gui_selection_state_changed({ element = { valid = true, tags = { ssk_ui = "period" }, selected_index = 3 }, player_index = 1 })
assert(storage.ui[1].period == 3600)
-- eras: fixed point
local g = storage.graph
print("eras:", g.nodes["item/inserter"].era, g.nodes["item/logistic-science-pack"].era, g.nodes["item/plastic-bar"].era, g.nodes["item/uranium-238"].era)
print("depth:", g.nodes["item/iron-plate"].depth, g.nodes["item/electronic-circuit"].depth, g.nodes["item/inserter"].depth, g.nodes["item/logistic-science-pack"].depth)
assert(g.nodes["item/inserter"].era == 1 and g.nodes["item/plastic-bar"].era == 2 and g.nodes["item/uranium-238"].era == 2)
handlers.on_gui_click({ element = { valid = true, name = "x", tags = { ssk_ui = "rt_margin" } }, player_index = 1 })
assert(player.gui.screen.ssk_test_frame, "render test not open")
handlers.on_gui_click({ element = { valid = true, name = "x", tags = { ssk_rt = "mode" } }, player_index = 1 })
handlers.on_gui_click({ element = { valid = true, name = "x", tags = { ssk_rt = "randomize" } }, player_index = 1 })
handlers["cmd_sankey-probe"]({ player_index = 1 })
for _, mm in ipairs(machines) do mm.force = FORCE end; player.selected = machines[1]; handlers["cmd_sankey-probe"]({ player_index = 1 })
for t = game.tick + 1, game.tick + 601 do game.tick = t; machines[1].products_finished = machines[1].products_finished + (t % 96 == 0 and 1 or 0); handlers.on_tick({ tick = t }) end
handlers.cc()
handlers["cmd_sankey-export"]({ player_index = 1 })
nth[3600]({ tick = 18000 })
for n, d in pairs(WRITES) do print("WROTE", n, #d) end
local f = io.open(TESTDIR .. "/out/latest.json", "w"); f:write(WRITES["production-flow/latest.json"]); f:close()
dofile(TESTDIR .. "/sk_test.lua")
dofile(TESTDIR .. "/bal_test.lua")
dofile(TESTDIR .. "/groups_test.lua")
dofile(TESTDIR .. "/fx_test.lua")
dofile(TESTDIR .. "/drawing_test.lua")
dofile(TESTDIR .. "/hover_labels_test.lua")
dofile(TESTDIR .. "/split_test.lua")
dofile(TESTDIR .. "/history_test.lua")
dofile(TESTDIR .. "/readability_test.lua")
dofile(TESTDIR .. "/balance_readability_test.lua")
dofile(TESTDIR .. "/full_readability_test.lua")
dofile(TESTDIR .. "/recipe_api_test.lua")
dofile(TESTDIR .. "/selection_refresh_test.lua")
dofile(TESTDIR .. "/plain_names_test.lua")
dofile(TESTDIR .. "/usability_test.lua")
dofile(TESTDIR .. "/chest_stock_test.lua")
dofile(TESTDIR .. "/material_picker_test.lua")
print("ALL OK")
