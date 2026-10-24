local Gr = TREQ("scripts.groups")
local saved_subgroups, saved_groups = prototypes.item_subgroup, prototypes.item_group
local modtab = { name = "mod-metallurgy", order = "z", localised_name = { "item-group-name.mod-metallurgy" } }
local base = { name = "intermediate-products", order = "c" }
local first = { name = "z-first", order = "a", group = modtab, localised_name = { "item-subgroup-name.z-first" } }
local second = { name = "a-second", order = "b", group = modtab }
prototypes.item_group = { [modtab.name] = modtab, [base.name] = base }
prototypes.item_subgroup = { [first.name] = first, [second.name] = second,
  ["base-parts"] = { name = "base-parts", order = "a", group = base } }
local old_item = rawget(prototypes.item, "mod-ingot")
local old_fluid = rawget(prototypes.fluid, "mod-acid")
prototypes.item["mod-ingot"] = { name = "mod-ingot", subgroup = first }
prototypes.fluid["mod-acid"] = { name = "mod-acid", subgroup = second }
assert(Gr.of(1, "item/iron-plate") == "plates", "curated defaults must take precedence")
assert(Gr.of(1, "item/mod-ingot") == "sub:z-first", "mod item fallback")
assert(Gr.of(1, "fluid/mod-acid") == "sub:a-second", "mod fluid fallback")
local a, b = Gr.info(1, "sub:z-first"), Gr.info(1, "sub:a-second")
assert(a.super == "tab:mod-metallurgy" and b.super == a.super, "preserve mod crafting tab")
assert(a.color == b.color and a.color == Gr.info(2, a.id).color, "stable tab colour")
assert(Gr.less(a, b), "prototype order takes precedence over alphabetical name")
assert(a.localised_name == first.localised_name and a.super_localised_name == modtab.localised_name)
assert(Gr.info(1, "sub:base-parts").super == "intermediates", "base crafting tab fallback")
local found = {}
for _, g in ipairs(Gr.list(1)) do found[g.id] = true end
assert(found[a.id] and found[b.id] and found.plates, "mod fallback groups must be selectable")
local custom = Gr.create(1, "Test alloys", "components")
Gr.assign(1, "item/mod-ingot", custom)
assert(Gr.of(1, "item/mod-ingot") == custom, "player override wins")
assert(Gr.of(2, "item/mod-ingot") == a.id, "overrides are per player")
Gr.unassign(1, "item/mod-ingot")
assert(Gr.of(1, "item/mod-ingot") == a.id, "default restores mod fallback")
Gr.state(1).custom[custom] = nil
local modcustom = Gr.create(1, "Special alloys", a.super)
local ci = Gr.info(1, modcustom)
assert(ci.super_order == a.super_order and ci.color == a.color, "custom group keeps mod parent order and colour")
Gr.state(1).custom[modcustom] = nil
local compat = { name = "old-subgroup", order = "c", group = modtab }
setmetatable(compat, { __index = function(_, key) error("unsupported prototype property " .. key) end })
prototypes.item_subgroup[compat.name] = compat
assert(Gr.info(1, "sub:old-subgroup").name == "Old subgroup", "older subgroup localisation fallback")
assert(Gr.info(1, "sub:missing").super == "other", "missing subgroup fallback")
prototypes.item["mod-ingot"], prototypes.fluid["mod-acid"] = old_item, old_fluid
prototypes.item_subgroup, prototypes.item_group = saved_subgroups, saved_groups
print("GROUP TESTS OK")
