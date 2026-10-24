-- Default grouping (see project doc default-groups.md). Two levels: super -> group.
-- color = palette index (shared/palette.lua), shared by all groups in a super-group.
-- Items not listed fall back to their Factorio subgroup (scripts/groups.lua).

local supers = {
  { id = "raw",        name = "Raw",        color = 17 },
  { id = "smelting",   name = "Smelting",   color = 4 },
  { id = "components", name = "Components", color = 2 },
  { id = "oil",        name = "Oil",        color = 13 },
  { id = "nuclear",    name = "Nuclear",    color = 9 },
  { id = "power",      name = "Power",      color = 17 },
  { id = "logistics",  name = "Logistics",  color = 17 },
  { id = "rocket",     name = "Rocket",     color = 6 },
  { id = "science",    name = "Science",    color = 8 },
  { id = "space",      name = "Space",      color = 12 },
  { id = "vulcanus",   name = "Vulcanus",   color = 5 },
  { id = "fulgora",    name = "Fulgora",    color = 6 },
  { id = "gleba",      name = "Gleba",      color = 3 },
  { id = "aquilo",     name = "Aquilo",     color = 7 },
  { id = "production", name = "Production", color = 11 },
  { id = "military",   name = "Military",   color = 1 },
  { id = "intermediates", name = "Other intermediates", color = 15 },
  { id = "other",      name = "Other",      color = 17 },
}

-- Factorio item group (crafting-menu tab) -> lane, for items not listed below
local tab_to_super = {
  ["logistics"] = "logistics", ["production"] = "production", ["combat"] = "military",
  ["intermediate-products"] = "intermediates", ["space"] = "space", ["fluids"] = "raw",
}

-- { group id, display name, super id, { items... } }   ("fluid:" prefix = fluid)
local groups = {
  { "ores", "Ores", "raw", { "iron-ore", "copper-ore", "stone", "coal", "uranium-ore" } },
  { "nature", "Nature", "raw", { "wood", "raw-fish" } },
  { "base-fluids", "Base fluids", "raw", { "fluid:water", "fluid:crude-oil" } },
  { "plates", "Plates", "smelting", { "iron-plate", "copper-plate", "steel-plate", "stone-brick" } },
  { "mechanical", "Mechanical", "components", { "iron-gear-wheel", "iron-stick", "pipe" } },
  { "electronics", "Electronics", "components", { "copper-cable", "electronic-circuit", "advanced-circuit", "processing-unit" } },
  { "assemblies", "Assemblies", "components", { "engine-unit", "electric-engine-unit", "flying-robot-frame", "low-density-structure" } },
  { "oil-fractions", "Oil fractions", "oil", { "fluid:heavy-oil", "fluid:light-oil", "fluid:petroleum-gas", "fluid:lubricant" } },
  { "chemicals", "Chemicals", "oil", { "plastic-bar", "sulfur", "fluid:sulfuric-acid", "explosives", "battery" } },
  { "fuels", "Fuels", "oil", { "solid-fuel", "rocket-fuel" } },
  { "uranium", "Uranium", "nuclear", { "uranium-235", "uranium-238", "uranium-fuel-cell", "depleted-uranium-fuel-cell", "nuclear-fuel" } },
  { "steam", "Steam", "power", { "fluid:steam" } },
  { "barrels", "Barrels", "logistics", { "barrel" } },
  { "rocket", "Rocket", "rocket", { "rocket-part" } },
  { "science-packs", "Science packs", "science", {
      "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack", "space-science-pack", "metallurgic-science-pack",
      "electromagnetic-science-pack", "agricultural-science-pack", "cryogenic-science-pack", "promethium-science-pack" } },
  { "asteroid-chunks", "Asteroid chunks", "space", { "metallic-asteroid-chunk", "carbonic-asteroid-chunk", "oxide-asteroid-chunk", "promethium-asteroid-chunk" } },
  { "space-products", "Space products", "space", { "carbon", "ice", "fluid:thruster-fuel", "fluid:thruster-oxidizer" } },
  { "lava-metals", "Lava & metals", "vulcanus", { "fluid:lava", "fluid:molten-iron", "fluid:molten-copper", "calcite" } },
  { "tungsten", "Tungsten", "vulcanus", { "tungsten-ore", "tungsten-carbide", "tungsten-plate" } },
  { "scrap", "Scrap", "fulgora", { "scrap" } },
  { "holmium", "Holmium", "fulgora", { "holmium-ore", "fluid:holmium-solution", "holmium-plate", "fluid:electrolyte" } },
  { "em-components", "EM components", "fulgora", { "superconductor", "supercapacitor" } },
  { "crops", "Crops", "gleba", { "yumako-seed", "jellynut-seed", "yumako", "jellynut", "yumako-mash", "jelly", "tree-seed" } },
  { "bio-processing", "Bio-processing", "gleba", { "nutrients", "bioflux", "spoilage", "iron-bacteria", "copper-bacteria" } },
  { "bio-products", "Bio-products", "gleba", { "carbon-fiber", "pentapod-egg", "biter-egg" } },
  { "aquilo-chem", "Aquilo chemistry", "aquilo", { "fluid:ammoniacal-solution", "fluid:ammonia", "fluid:fluorine", "fluid:lithium-brine", "fluid:fluoroketone-hot", "fluid:fluoroketone-cold" } },
  { "lithium", "Lithium", "aquilo", { "lithium", "lithium-plate" } },
  { "endgame", "Endgame parts", "aquilo", { "quantum-processor", "fusion-power-cell", "fluid:fusion-plasma" } },
}

local D = { supers = {}, super_order = {}, groups = {}, group_order = {}, items = {}, tab_to_super = tab_to_super }
for i, s in ipairs(supers) do
  D.supers[s.id] = s
  D.super_order[s.id] = i
end
for i, g in ipairs(groups) do
  local id, name, super, items = g[1], g[2], g[3], g[4]
  D.groups[id] = { id = id, name = name, super = super }
  D.group_order[id] = i
  for _, it in ipairs(items) do
    local key
    if string.sub(it, 1, 6) == "fluid:" then key = "fluid/" .. string.sub(it, 7) else key = "item/" .. it end
    D.items[key] = id
  end
end
return D
