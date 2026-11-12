local Loc = require("scripts.locale")
-- Default grouping (see project doc default-groups.md). Two levels: super -> group.
-- color = palette index (shared/palette.lua), shared by all groups in a super-group.
-- Items not listed fall back to their Factorio subgroup (scripts/groups.lua).

local supers = {
  { id = "raw",        name = Loc("groups-default-raw"),        color = 17 },
  { id = "smelting",   name = Loc("groups-default-smelting"),   color = 4 },
  { id = "components", name = Loc("groups-default-components"), color = 2 },
  { id = "oil",        name = Loc("groups-default-oil"),        color = 13 },
  { id = "nuclear",    name = Loc("groups-default-nuclear"),    color = 9 },
  { id = "power",      name = Loc("machine-status-power"),      color = 17 },
  { id = "logistics",  name = Loc("groups-default-logistics"),  color = 17 },
  { id = "rocket",     name = Loc("groups-default-rocket"),     color = 6 },
  { id = "science",    name = Loc("groups-default-science"),    color = 8 },
  { id = "space",      name = Loc("groups-default-space"),      color = 12 },
  { id = "vulcanus",   name = Loc("groups-default-vulcanus"),   color = 5 },
  { id = "fulgora",    name = Loc("groups-default-fulgora"),    color = 6 },
  { id = "gleba",      name = Loc("groups-default-gleba"),      color = 3 },
  { id = "aquilo",     name = Loc("groups-default-aquilo"),     color = 7 },
  { id = "production", name = Loc("groups-default-production"), color = 11 },
  { id = "military",   name = Loc("groups-default-military"),   color = 1 },
  { id = "intermediates", name = Loc("groups-default-other-intermediates"), color = 15 },
  { id = "other",      name = Loc("material-picker-other"),      color = 17 },
}

-- Factorio item group (crafting-menu tab) -> lane, for items not listed below
local tab_to_super = {
  ["logistics"] = "logistics", ["production"] = "production", ["combat"] = "military",
  ["intermediate-products"] = "intermediates", ["space"] = "space", ["fluids"] = "raw",
}

-- { group id, display name, super id, { items... } }   ("fluid:" prefix = fluid)
local groups = {
  { "ores", Loc("groups-default-ores"), "raw", { "iron-ore", "copper-ore", "stone", "coal", "uranium-ore" } },
  { "nature", Loc("groups-default-nature"), "raw", { "wood", "raw-fish" } },
  { "base-fluids", Loc("groups-default-base-fluids"), "raw", { "fluid:water", "fluid:crude-oil" } },
  { "plates", Loc("groups-default-plates"), "smelting", { "iron-plate", "copper-plate", "steel-plate", "stone-brick" } },
  { "mechanical", Loc("groups-default-mechanical"), "components", { "iron-gear-wheel", "iron-stick", "pipe" } },
  { "electronics", Loc("groups-default-electronics"), "components", { "copper-cable", "electronic-circuit", "advanced-circuit", "processing-unit" } },
  { "assemblies", Loc("groups-default-assemblies"), "components", { "engine-unit", "electric-engine-unit", "flying-robot-frame", "low-density-structure" } },
  { "oil-fractions", Loc("groups-default-oil-fractions"), "oil", { "fluid:heavy-oil", "fluid:light-oil", "fluid:petroleum-gas", "fluid:lubricant" } },
  { "chemicals", Loc("groups-default-chemicals"), "oil", { "plastic-bar", "sulfur", "fluid:sulfuric-acid", "explosives", "battery" } },
  { "fuels", Loc("groups-default-fuels"), "oil", { "solid-fuel", "rocket-fuel" } },
  { "uranium", Loc("groups-default-uranium"), "nuclear", { "uranium-235", "uranium-238", "uranium-fuel-cell", "depleted-uranium-fuel-cell", "nuclear-fuel" } },
  { "steam", Loc("groups-default-steam"), "power", { "fluid:steam" } },
  { "barrels", Loc("groups-default-barrels"), "logistics", { "barrel" } },
  { "rocket", Loc("groups-default-rocket"), "rocket", { "rocket-part" } },
  { "science-packs", Loc("groups-default-science-packs"), "science", {
      "automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack",
      "production-science-pack", "utility-science-pack", "space-science-pack", "metallurgic-science-pack",
      "electromagnetic-science-pack", "agricultural-science-pack", "cryogenic-science-pack", "promethium-science-pack" } },
  { "asteroid-chunks", Loc("groups-default-asteroid-chunks"), "space", { "metallic-asteroid-chunk", "carbonic-asteroid-chunk", "oxide-asteroid-chunk", "promethium-asteroid-chunk" } },
  { "space-products", Loc("groups-default-space-products"), "space", { "carbon", "ice", "fluid:thruster-fuel", "fluid:thruster-oxidizer" } },
  { "lava-metals", Loc("groups-default-lava-metals"), "vulcanus", { "fluid:lava", "fluid:molten-iron", "fluid:molten-copper", "calcite" } },
  { "tungsten", Loc("groups-default-tungsten"), "vulcanus", { "tungsten-ore", "tungsten-carbide", "tungsten-plate" } },
  { "scrap", Loc("groups-default-scrap"), "fulgora", { "scrap" } },
  { "holmium", Loc("groups-default-holmium"), "fulgora", { "holmium-ore", "fluid:holmium-solution", "holmium-plate", "fluid:electrolyte" } },
  { "em-components", Loc("groups-default-em-components"), "fulgora", { "superconductor", "supercapacitor" } },
  { "crops", Loc("groups-default-crops"), "gleba", { "yumako-seed", "jellynut-seed", "yumako", "jellynut", "yumako-mash", "jelly", "tree-seed" } },
  { "bio-processing", Loc("groups-default-bio-processing"), "gleba", { "nutrients", "bioflux", "spoilage", "iron-bacteria", "copper-bacteria" } },
  { "bio-products", Loc("groups-default-bio-products"), "gleba", { "carbon-fiber", "pentapod-egg", "biter-egg" } },
  { "aquilo-chem", Loc("groups-default-aquilo-chemistry"), "aquilo", { "fluid:ammoniacal-solution", "fluid:ammonia", "fluid:fluorine", "fluid:lithium-brine", "fluid:fluoroketone-hot", "fluid:fluoroketone-cold" } },
  { "lithium", Loc("groups-default-lithium"), "aquilo", { "lithium", "lithium-plate" } },
  { "endgame", Loc("groups-default-endgame-parts"), "aquilo", { "quantum-processor", "fusion-power-cell", "fluid:fusion-plasma" } },
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
    if string.sub(it, 1, 6) == "fluid:" then key = Loc.join("fluid/", string.sub(it, 7)) else key = Loc.join("item/", it) end
    D.items[key] = id
  end
end
return D
