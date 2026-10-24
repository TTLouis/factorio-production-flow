-- Reject the removed property exactly as the real 2.1 LuaObject does.
local Graph = TREQ("scripts.graph")
local old_prototypes, old_graph = prototypes, storage.graph
local old_version = script.active_mods.base
local function recipe(fields, forbidden)
  fields.ingredients = {{type="item", name="iron-ore", amount=1}}
  fields.products = {{type="item", name="iron-plate", amount=1}}
  fields.energy, fields.enabled = 1, true
  return setmetatable(fields, {__index=function(_, key)
    assert(key ~= forbidden, "accessed unavailable recipe API: "..key)
  end})
end
prototypes = {technology={}, recipe={
  smelting=recipe({categories={"smelting", "metallurgy"}}, "category"),
  recycling=recipe({categories={"crafting", "recycling"}}, "category"),
}}
script.active_mods.base = "2.1.23"
local g = Graph.build()
assert(g.recipes.smelting.category == "smelting, metallurgy")
assert(not g.recipes.smelting.reversing and g.recipes.recycling.reversing)
script.active_mods.base = "2.0.77"
prototypes.recipe = {smelting=recipe({category="smelting"}, "categories")}
assert(Graph.build().recipes.smelting.category == "smelting")
prototypes, storage.graph, script.active_mods.base = old_prototypes, old_graph, old_version
print("Recipe API 2.0 / 2.1 compatibility OK")
