-- Isolated cells benchmark hook; never packaged. On the first tick of each
-- benchmark run it either leaves the save without cells (baseline) or puts every
-- sampled machine into two overlapping cells: one per surface plus one per group
-- of `size` machines, so every craft takes the shared attribution path. With
-- overlap=false only the groups exist; `limit` caps how many groups are made.
local Cells = require("scripts.cells")
local cfg = require("scripts.cells_benchmark_config")

local B = {}

function B.tick()
  if storage.cell_bench_ready then return end
  storage.cell_bench_ready = true
  if not cfg.cells then
    storage.production_cells, storage.cell_units = nil, nil
    log("CELL BENCH BASELINE: no cells")
    return
  end
  local by_surface = {}
  for _, rec in pairs(storage.machines or {}) do
    local e = rec.e
    if e and e.valid and rec.eligible then
      local list = by_surface[e.surface.index]
      if not list then list = {}; by_surface[e.surface.index] = list end
      list[#list + 1] = e
    end
  end
  local surfaces = {}
  for sidx in pairs(by_surface) do surfaces[#surfaces + 1] = sidx end
  table.sort(surfaces)
  local records, id, machines, groups = {}, 0, 0, 0
  for _, sidx in ipairs(surfaces) do
    local list = by_surface[sidx]
    table.sort(list, function(a, b) return a.unit_number < b.unit_number end)
    local all
    if cfg.overlap ~= false then
      id = id + 1
      all = { id = id, name = "All " .. sidx, surface_index = sidx, members = {}, since = game.tick, display_item = false }
      records[id] = all
    end
    local group
    for i, e in ipairs(list) do
      if all then all.members[e.unit_number] = e end
      if (i - 1) % cfg.size == 0 then
        if cfg.limit and cfg.limit > 0 and groups >= cfg.limit then break end
        groups = groups + 1
        id = id + 1
        group = { id = id, name = "Cell " .. id, surface_index = sidx, members = {}, since = game.tick, display_item = false }
        records[id] = group
      end
      group.members[e.unit_number] = e
      machines = machines + 1
    end
  end
  storage.production_cells = { next_id = id + 1, records = records, drafts = {}, deletions = {} }
  Cells.reindex()
  log(string.format("CELL BENCH CELLS: %d cells on %d surfaces, %d machines in small cells, overlap=%s",
    id, #surfaces, machines, tostring(cfg.overlap ~= false)))
end

return B
