-- M1: static bipartite recipe graph (D1, D3)
-- Vertices: "item/<name>", "fluid/<name>", "recipe/<name>".
-- Stored in storage.graph; rebuilt on init / configuration change.

local G = {}

function G.key(t, n) return t .. "/" .. n end

-- expected output per craft, and the part of it that productivity applies to
local function expected(p)
  local amt = p.amount
  if not amt then amt = ((p.amount_min or 0) + (p.amount_max or 0)) / 2 end
  local prob = p.probability or 1
  local extra = p.extra_count_fraction or 0
  local ign = math.min(p.ignored_by_productivity or 0, amt)
  return amt * prob + extra, math.max(0, amt - ign) * prob + extra
end

-- recipes that undo other recipes: excluded from tiering, rendered as loop-backs (D4)
local function is_reversing(rp, categories)
  for _, category in ipairs(categories) do
    if category == "recycling" then return true end
  end
  local sg = rp.subgroup and rp.subgroup.name
  return sg == "empty-barrel"
end

function G.build()
  local g = { nodes = {}, recipes = {}, n_nodes = 0, n_recipes = 0, n_reversing = 0 }
  local version = script and script.active_mods and script.active_mods.base or "2.0"
  local major, minor = version:match("^(%d+)%.(%d+)")
  local multiple_categories = tonumber(major) > 2 or (tonumber(major) == 2 and tonumber(minor) >= 1)

  local function node(t, n)
    local k = G.key(t, n)
    local nd = g.nodes[k]
    if not nd then
      nd = { key = k, type = t, name = n, producers = {}, consumers = {} }
      g.nodes[k] = nd
      g.n_nodes = g.n_nodes + 1
    end
    return nd
  end

  for name, rp in pairs(prototypes.recipe) do
    -- 2.1 removed category in favor of categories. Accessing a removed LuaObject
    -- property throws, so choose the API before reading the prototype.
    local categories = multiple_categories and rp.categories or { rp.category }
    local r = {
      name = name,
      category = table.concat(categories, ", "),
      energy = rp.energy,
      hidden = rp.hidden,
      reversing = is_reversing(rp, categories),
      ingredients = {},
      products = {},
    }
    for _, ing in pairs(rp.ingredients) do
      if ing.type == "item" or ing.type == "fluid" then
        local nd = node(ing.type, ing.name)
        r.ingredients[#r.ingredients + 1] = { key = nd.key, amount = ing.amount }
        nd.consumers[#nd.consumers + 1] = name
      end
    end
    for _, p in pairs(rp.products) do
      if p.type == "item" or p.type == "fluid" then
        local nd = node(p.type, p.name)
        local base, elig = expected(p)
        r.products[#r.products + 1] = { key = nd.key, amount = base, prod = elig }
        nd.producers[#nd.producers + 1] = name
      end
    end
    g.recipes[name] = r
    g.n_recipes = g.n_recipes + 1
    if r.reversing then g.n_reversing = g.n_reversing + 1 end
  end

  G.compute_eras(g)
  storage.graph = g
  return g
end

-- Tech eras (D25): how far into the tech tree a recipe / item is.
--   pack rank(p)  = 1 + era of the recipe that makes pack p   (red = 1, green = 2, …)
--   era(tech)     = max(rank of its science packs, era of its prerequisites)
--                   (trigger techs without packs inherit from prerequisites)
--   era(recipe)   = 0 if enabled at start, else min era of the techs unlocking it
--   era(item)     = min era over its non-reversing producing recipes (raw = 0)
function G.compute_eras(g)
  -- Order-independent fixed point (the old recursive version cached values computed
  -- while inside a cycle, so some items could end up at era 0 depending on load order).
  local techs = prototypes.technology
  local unlock = {}
  for tname, t in pairs(techs) do
    for _, eff in pairs(t.effects or {}) do
      if eff.type == "unlock-recipe" and eff.recipe then
        unlock[eff.recipe] = unlock[eff.recipe] or {}
        table.insert(unlock[eff.recipe], tname)
      end
    end
  end
  local INF = math.huge
  local rera, tera = {}, {}
  for rn in pairs(g.recipes) do
    local rp = prototypes.recipe[rn]
    rera[rn] = (rp and rp.enabled) and 0 or INF
  end
  for tn in pairs(techs) do tera[tn] = INF end

  local function item_era(key)
    local nd = g.nodes[key]
    local e, any = INF, false
    for _, rn in ipairs(nd and nd.producers or {}) do
      if not g.recipes[rn].reversing then
        any = true
        if rera[rn] < e then e = rera[rn] end
      end
    end
    if not any then return 0 end -- raw (mined / pumped / gathered)
    return e
  end

  -- values only ever decrease from INF, so this terminates
  for _ = 1, 100 do
    local changed = false
    for tn, t in pairs(techs) do
      local e = 0
      for _, ing in pairs(t.research_unit_ingredients or {}) do
        local r = item_era("item/" .. ing.name) + 1
        if r > e then e = r end
      end
      for pn in pairs(t.prerequisites or {}) do
        if tera[pn] > e then e = tera[pn] end
      end
      if e < tera[tn] then tera[tn] = e; changed = true end
    end
    for rn in pairs(g.recipes) do
      local e = rera[rn]
      for _, tn in ipairs(unlock[rn] or {}) do
        if tera[tn] < e then e = tera[tn] end
      end
      if e < rera[rn] then rera[rn] = e; changed = true end
    end
    if not changed then break end
  end

  -- techs that can never be researched by this rule (pack made only by a recipe the same
  -- tech unlocks, script-unlocked packs…) go after everything else instead of to era 0
  local maxf = 0
  for _, e in pairs(tera) do if e ~= INF and e > maxf then maxf = e end end
  for rn, r in pairs(g.recipes) do
    if rera[rn] == INF then
      r.era = unlock[rn] and (maxf + 1) or 0 -- 0 = never unlocked by a tech (scripted / hidden)
    else
      r.era = rera[rn]
    end
    rera[rn] = r.era
  end
  g.max_era = 0
  for key, nd in pairs(g.nodes) do
    local e = item_era(key)
    if e == INF then e = 0 end
    nd.era = e
    if e > g.max_era then g.max_era = e end
  end
  G.compute_depth(g)
end

-- Static production depth: longest chain from raw over each item's earliest-era producers
-- (cycle-safe fixed point). Used to place items that are idle right now, so an idle
-- electric engine is not drawn as if it were a raw resource.
function G.compute_depth(g)
  local depth = {}
  for key, nd in pairs(g.nodes) do
    local raw = true
    for _, rn in ipairs(nd.producers) do if not g.recipes[rn].reversing then raw = false end end
    depth[key] = raw and 0 or nil
  end
  for _ = 1, 60 do
    local changed = false
    for key, nd in pairs(g.nodes) do
      if depth[key] ~= 0 then
        local best
        for _, rn in ipairs(nd.producers) do
          local r = g.recipes[rn]
          if not r.reversing and r.era == nd.era then
            local d, ok = 0, true
            for _, ing in ipairs(r.ingredients) do
              local x = depth[ing.key]
              if x == nil then ok = false break end
              if x + 1 > d then d = x + 1 end
            end
            if ok and (not best or d < best) then best = d end
          end
        end
        if best and best ~= depth[key] and (depth[key] == nil or best < depth[key]) then
          depth[key] = best; changed = true
        end
      end
    end
    if not changed then break end
  end
  for key, nd in pairs(g.nodes) do nd.depth = depth[key] or 0 end
end

function G.get()
  return storage.graph or G.build()
end

-- "[item=iron-plate]" style rich text for any vertex key
function G.rt(key)
  local t, n = string.match(key, "^(%a+)/(.+)$")
  if not t then return key end
  return "[" .. t .. "=" .. n .. "]"
end

return G
