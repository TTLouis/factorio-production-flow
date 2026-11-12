local Sampler = (TREQ or require)("scripts.sampler")
local saved_storage, saved_game, saved_settings = storage, game, settings

local function check(recipe, machine, before, after, normal)
  storage = { graph = { recipes = { [recipe.name] = recipe } } }
  game = { tick = 0, surfaces = {} }
  settings = { global = { ["ssk-window-seconds"] = { value = 60 },
    ["ssk-entities-per-tick"] = { value = 1 } } }
  Sampler.init()

  local force_recipe = { name = recipe.name, productivity_bonus = machine.research }
  local entity = { valid = true, type = machine.type or "assembling-machine", unit_number = 1,
    surface = { index = 1 }, products_finished = 0, crafting_speed = machine.speed,
    productivity_bonus = machine.bonus, crafting_progress = before.crafting, bonus_progress = before.bonus,
    force = { recipes = { [recipe.name] = force_recipe } } }
  entity.get_recipe = function() return force_recipe end
  Sampler.add(entity)
  entity.products_finished, entity.crafting_progress, entity.bonus_progress =
    after.total, after.crafting, after.bonus
  if after.idle then
    entity.get_recipe = function() return nil end
    entity.previous_recipe = { name = { name = recipe.name } }
  end
  game.tick = 1
  Sampler.on_tick(1)
  local sample = storage.bins[1].rec[1][recipe.name]
  assert(sample.c == after.total and Sampler.normal_crafts(sample) == normal,
    recipe.name .. " expected " .. normal .. " regular crafts, got " .. Sampler.normal_crafts(sample))
end

local cracking = { name = "heavy-oil-cracking", energy = 2 }
local chemical_plant = { speed = 1.6, bonus = 0.18 }
-- A pending bonus pays out while the regular craft is still in progress.
check(cracking, chemical_plant, { crafting = 0.8933333333, bonus = 1 },
  { total = 1, crafting = 0.9066666667, bonus = 0.0035043 }, 0)
-- The bar fills while the sampler is away, with the payout still pending.
check(cracking, chemical_plant, { crafting = 0.7466666667, bonus = 0.737182 },
  { total = 2, crafting = 0.2133333333, bonus = 1 }, 2)

check({ name = "steel-plate", energy = 3.2 }, { type = "furnace", speed = 2, bonus = 0, research = 0.7 },
  { crafting = 1, bonus = 1 }, { total = 2, crafting = 0, bonus = 0.003, idle = true }, 1)
check({ name = "capped", energy = 2, max_productivity = 0.8 },
  { speed = 2.4, bonus = 0.6, research = 0.7 },
  { crafting = 0.25, bonus = 1 }, { total = 1, crafting = 0.27, bonus = 0.02 }, 0)

-- A very fast modded machine can hide enough progress to make either count fit.
check({ name = "fast", energy = 1 }, { speed = 120, bonus = 1 },
  { crafting = 0, bonus = 1 }, { total = 1, crafting = 0, bonus = 1 }, 0.5)

storage, game, settings = saved_storage, saved_game, saved_settings
print("PRODUCTIVITY OK: research, furnace fallback, recipe cap, pending payouts and ambiguous progress")
