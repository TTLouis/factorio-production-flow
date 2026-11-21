local S = require("scripts.cell_rail_suggestions")
prototypes = { item = { iron = { name = "iron" }, copper = { name = "copper" } }, fluid = { water = { name = "water" } } }
local name = "[item=iron] [img=item/iron] [fluid=water] [img=item/copper] [item=missing] [img=virtual-signal/iron]"
local materials = S.materials(name)
assert(materials["item/iron"] and materials["item/copper"] and materials["fluid/water"])
assert(not materials["item/missing"] and not materials["item/virtual-signal/iron"])
local net = { ["item/iron"] = -2, ["item/copper"] = 3, ["fluid/water"] = 0 }
assert(S.role(name, net) == "both")
assert(S.role("[item=iron][item=iron]", net) == "import")
assert(S.role("[img=item/copper]", net) == "export")
assert(S.role("[fluid=water][item=missing]", net) == nil)
local ports = S.ports(name, "both", net)
assert(ports.inputs["item/iron"] and ports.outputs["item/copper"])
assert(not ports.outputs["item/iron"] and not ports.inputs["item/copper"] and not ports.inputs["fluid/water"])
ports = S.ports(name, "import", net)
assert(ports.inputs["item/iron"] and not next(ports.outputs))
local Capacity = require("scripts.cell_capacity")
local old_rates, old_flows = Capacity.rates, Capacity.flows
Capacity.rates = function(members, shared, inputs, estimate)
  assert(inputs == nil and estimate == true)
  return {fixture = {normal = 1, bonus = 0}}, { ["item/coal"] = { fixture = 0.6 } }
end
Capacity.flows = function(_, consume, produce)
  consume("fixture", "item/iron", 2)
  produce("fixture", "item/copper", 3)
end
storage = {cell_burner_prototypes = {}, graph = {recipes = {}}}
net = S.net({})
assert(net["item/iron"] == -2 and net["item/copper"] == 3 and net["item/coal"] == -0.6)
Capacity.rates, Capacity.flows = old_rates, old_flows
local Sampler = require("scripts.sampler")
local old_current, old_productivity = Sampler.current_recipe, Sampler.craft_productivity
Sampler.current_recipe = function() return "fixture" end
Sampler.craft_productivity = function() return 0 end
prototypes.item.coal = {name = "coal", fuel_value = 100, fuel_categories = {"chemical"}}
storage.cell_burner_prototypes.burner = {fuel_categories = {chemical = true}, effectivity = 1}
storage.graph.recipes.fixture = {energy = 1, ingredients = {}, products = {}}
local machine = {name = "burner", crafting_speed = 1, burner = {currently_burning = {name = prototypes.item.coal, quality = "normal"}},
  prototype = {get_max_energy_usage = function() return 1 end}}
local rates, fuels = Capacity.rates({[1] = machine}, nil, nil, true)
assert(rates.fixture and math.abs(fuels["item/coal"].fixture - 0.6) < 1e-9,
  "A LuaBurner currently_burning item pair returns the fuel prototype")
Sampler.current_recipe, Sampler.craft_productivity = old_current, old_productivity
print("Cell rail suggestions OK")
