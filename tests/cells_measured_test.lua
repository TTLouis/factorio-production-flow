-- Measured cell throughput: sampler attribution per cell, roll-up through the
-- rings, clipping to the cell's creation, shared-machine exclusion, membership
-- changes, purge on delete, and the measured/capacity chart modes.
return function(handlers, nth)
  local Cells = TREQ("scripts.cells")
  local Flow = TREQ("scripts.cell_flow")
  local Sampler = TREQ("scripts.sampler")

  local nauvis, FORCE = game.surfaces[1], game.forces.player
  local saved_cells, saved_units, saved_shared = storage.production_cells, storage.cell_units, storage.cell_shared_units

  local mine, next_unit = {}, 990000
  local function machine(x, recipe)
    next_unit = next_unit + 1
    local e = { valid = true, type = "assembling-machine", name = "assembling-machine-1", unit_number = next_unit,
      surface = nauvis, force = FORCE, position = { x = x, y = 40.5 }, crafting_speed = 1, productivity_bonus = 0,
      products_finished = 0, crafting_progress = 0, bonus_progress = 0, _r = recipe, _acc = 0, running = true }
    e.get_recipe = function() return { name = e._r } end
    mine[#mine + 1] = e
    Sampler.add(e)
    return e
  end
  -- Every recipe used here takes 1 s, so a running machine finishes 1 craft/s.
  local a = machine(0.5, "copper-cable")
  local b = machine(4.5, "electronic-circuit")
  local c = machine(8.5, "iron-gear-wheel")

  local function run(seconds)
    for _ = 1, seconds * 60 do
      local t = game.tick + 1
      game.tick = t
      for _, e in ipairs(mine) do
        if e.running then
          e._acc = e._acc + e.crafting_speed / 60
          local whole = math.floor(e._acc + 1e-9)
          e._acc = e._acc - whole
          e.products_finished = e.products_finished + whole
        end
      end
      handlers.on_tick({ tick = t })
      for _, n in ipairs({ 60, 300, 600 }) do
        if t % n == 0 and nth[n] then nth[n]({ tick = t }) end
      end
    end
  end
  local function near(value, expected, tolerance, what)
    assert(math.abs((value or 0) - expected) <= tolerance,
      string.format("%s: expected %.3f, got %.3f", what, expected, value or 0))
  end
  local function cps(rates, recipe) return rates[recipe] and rates[recipe].cps or 0 end

  -- Let the sampler seed the new machines before the cells exist.
  run(2)
  local created = game.tick
  local function cell(id, name, members)
    local m = {}
    for _, e in ipairs(members) do m[e.unit_number] = e end
    return { id = id, name = name, surface_index = 1, members = m, since = created, display_item = false }
  end
  storage.production_cells = { next_id = 3, records = { [1] = cell(1, "Circuits", { a, b }), [2] = cell(2, "Gears", { b, c }) },
    drafts = {}, deletions = {} }
  Cells.reindex()
  assert(storage.cell_units[b.unit_number][1] == 1 and storage.cell_units[b.unit_number][2] == 2,
    "A machine in two cells must be indexed for both, in id order")

  -- Phase 1: everything running.
  run(150)
  local r1 = Sampler.cell_rates(1, 1, 60, created)
  near(cps(r1, "copper-cable"), 1, 0.05, "cell 1 copper-cable")
  near(cps(r1, "electronic-circuit"), 1, 0.05, "cell 1 shared circuit")
  assert(cps(r1, "iron-gear-wheel") == 0, "Crafts of another cell's machine leaked into cell 1")
  local x1 = Sampler.cell_rates(1, 1, 60, created, true)
  near(cps(x1, "copper-cable"), 1, 0.05, "cell 1 exclusive copper-cable")
  assert(cps(x1, "electronic-circuit") < 1e-6, "Exclusive rates must leave out a machine shared with another cell")
  near(cps(Sampler.cell_rates(2, 1, 60, created), "iron-gear-wheel"), 1, 0.05, "cell 2 gear")

  -- A window longer than the cell's life is measured only since creation.
  local long, secs, requested = Sampler.cell_rates(1, 1, 600, created)
  assert(requested == 600, "Requested window must be the selected period")
  near(secs, 150, 2, "measured seconds since creation")
  near(cps(long, "copper-cable"), 1, 0.05, "rate over the clipped window")
  local young = Flow.build(1, { mode = "measured", period = 600 })
  assert(young.partial and young.mode == "measured", "A cell younger than the period must be marked partial")
  assert(young.nodes["recipe/copper-cable"].rate_line, "Measured recipe nodes need a utilisation line")
  near(young.utilisation, 1, 0.05, "full-speed utilisation")
  storage.production_cells.records[3] = { id = 3, parent_id = 1, surface_index = 1,
    members = {}, since = game.tick, name = "New child" }
  local parent_after_child = Flow.build(1, { mode = "measured", period = 600 })
  near(parent_after_child.seconds, young.seconds, 0.01, "parent history after creating a child")
  storage.production_cells.records[3] = nil

  -- Phase 2: the cable machine stops; half the cell's crafting time is idle.
  a.running = false
  run(120)
  local half = Flow.build(1, { mode = "measured", period = 60 })
  near(half.utilisation, 0.5, 0.05, "utilisation with one of two machines idle")
  assert(not half.partial, "A full window must not be marked partial")
  assert(not half.nodes["recipe/copper-cable"], "An idle recipe must not be charted in measured mode")
  local capacity = Flow.build(1, { mode = "capacity" })
  assert(capacity.mode == "capacity" and capacity.nodes["recipe/copper-cable"] and not capacity.nodes["recipe/copper-cable"].rate_line,
    "Capacity mode still charts every configured recipe")

  -- Phase 3: resume; the 600 s window spans fine bins and the 10 s ring.
  a.running = true
  run(430)
  local ten, ten_secs = Sampler.cell_rates(1, 1, 600, created)
  near(ten_secs, 600, 2, "full 600 s coverage")
  near(cps(ten, "copper-cable"), 0.8, 0.04, "rate across ring roll-up with 120 s idle")
  near(cps(ten, "electronic-circuit"), 1, 0.04, "steady machine across ring roll-up")

  -- All view: shared machines are excluded and nodes carry utilisation.
  local all = Flow.build(nil, { mode = "measured", period = 60 })
  assert(all.overlap and all.requested == 60, "All view must report the overlap and the requested window")
  assert(all.nodes["recipe/cell-1"].rate_line and all.nodes["recipe/cell-2"].rate_line,
    "Cell nodes need a utilisation line in measured mode")

  -- Membership change: crafts count for a cell only while the machine is a member.
  storage.production_cells.records[1].members[b.unit_number] = nil
  storage.production_cells.records[1].positions[b.unit_number] = nil
  Cells.reindex()
  assert(#storage.cell_units[b.unit_number] == 1, "Removed member must leave the cell index")
  run(60)
  local after = Sampler.cell_rates(1, 1, 60, created)
  assert(cps(after, "electronic-circuit") < 0.05, "A removed member's later crafts must not be attributed")
  near(cps(Sampler.cell_rates(2, 1, 60, created, true), "electronic-circuit"), 1, 0.05,
    "A machine no longer shared counts in the exclusive view")

  -- Deleting a cell purges its history from every resolution.
  Sampler.purge_cell(2)
  assert(not next((Sampler.cell_rates(2, 1, 600, created))), "Purged cell still has measured crafts")
  local function check(bin) assert(not (bin.cell and bin.cell[2]) and not (bin.cell_shared and bin.cell_shared[2]), "Purged cell left a bin") end
  for _, bin in pairs(storage.bins or {}) do check(bin) end
  for _, ring in ipairs(storage.rings or {}) do for _, bin in pairs(ring.bins) do check(bin) end end

  -- Parent and child inclusion is not sharing, but overlapping siblings are.
  local phase = game.tick
  local root = cell(10, "Parent", { a, b })
  local child = cell(11, "Child", { a })
  child.parent_id = 10
  root.since, child.since = phase, phase
  storage.production_cells = { next_id = 13, records = { [10] = root, [11] = child }, drafts = {} }
  Cells.reindex()
  run(65)
  near(cps(Sampler.cell_rates(10, 1, 60, phase, true), "copper-cable"), 1, 0.05, "parent inclusion is not overlap")
  near(cps(Sampler.cell_rates(11, 1, 60, phase, true), "copper-cable"), 1, 0.05, "child inclusion is not overlap")
  local sibling = cell(12, "Sibling", { a }); sibling.parent_id, sibling.since = 10, game.tick
  storage.production_cells.records[12] = sibling
  Cells.reindex()
  run(65)
  assert(cps(Sampler.cell_rates(11, 1, 60, phase, true), "copper-cable") < 0.05, "Sibling overlap must be excluded")
  near(cps(Sampler.cell_rates(10, 1, 60, phase, true), "copper-cable"), 1, 0.05, "Sibling overlap must not exclude parent")

  -- Restore the shared world for later tests.
  local drop = {}
  for _, e in ipairs(mine) do drop[e.unit_number] = true; storage.machines[e.unit_number] = nil; e.valid = false end
  local list = {}
  for _, u in ipairs(storage.mlist) do if not drop[u] then list[#list + 1] = u end end
  storage.mlist = list
  if storage.mcursor > #list then storage.mcursor = 1 end
  storage.production_cells, storage.cell_units, storage.cell_shared_units = saved_cells, saved_units, saved_shared
  print("CELL MEASURED PASS: per-cell attribution, exclusive shared, since clipping, ring roll-up, utilisation, membership change, purge, modes")
end
