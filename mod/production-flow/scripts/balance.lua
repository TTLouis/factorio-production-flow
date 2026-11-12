-- Balance tab: per item, is it in deficit (draining a buffer), in surplus (filling one),
-- held back by its supply, or over-built for its demand?
--
-- Inputs (all measured):
--   produced / consumed : force production statistics (window average)
--   machine utilisation : normal crafts / capacity (sum of crafting_speed / energy)
--   stock + trend       : physical chest contents, scanned in bounded batches

local Graph = require("scripts.graph")
local Model = require("scripts.model")
local Sampler = require("scripts.sampler")

local B = {}

B.NET_TOL = 0.05   -- |net| below 5 % of throughput counts as balanced
B.LOW = 0.85       -- machines below 85 % busy are "waiting"
B.HIGH = 0.95      -- machines above 95 % busy are "maxed"

B.STATUS = {
  stored = { order = 8, label = "Stock only", color = "0.7,0.7,0.7",
             help = "Stored in chests, with no measured production or consumption in this period." },
  deficit   = { order = 1, label = "Deficit",          color = "1,0.35,0.35",
                help = "Measured consumption exceeds production by more than 5%. Check stored supply and transport; chest stock gives an estimated time to empty when a drain is measured." },
  limited   = { order = 2, label = "Possible supply limit", color = "1,0.6,0.2",
                help = "Rates roughly balance, consumer utilisation is below 85% and producers are at least 95% busy. Check this item's supply and delivery before adding capacity; utilisation alone does not identify the cause." },
  starved   = { order = 3, label = "Low activity",          color = "1,0.8,0.3",
                help = "Rates roughly balance and both producer and consumer utilisation are below 85%. Check inputs, transport, power and demand; low utilisation alone does not prove an upstream bottleneck." },
  surplus   = { order = 4, label = "Surplus",          color = "1,0.9,0.3",
                help = "Measured production exceeds consumption by more than 5%. Output may be accumulating, exported or used outside tracked crafting machines; check recent stock trend." },
  overbuilt = { order = 5, label = "Spare capacity",    color = "0.45,0.7,1",
                help = "Rates roughly balance, producer utilisation is below 85% and consumers are at least 95% busy. Producer capacity may exceed current demand; check delivery and machine conditions." },
  ok        = { order = 6, label = "OK",               color = "0.5,0.9,0.5",
                help = "Measured rates match within 5%, with no utilisation warning detected. Some machines or uses may be outside the tracked data." },
  source    = { order = 7, label = "Source / sink",    color = "0.7,0.7,0.7",
                help = "Mined, pumped or consumed outside crafting machines (labs, fuel, building…): no machine data." },
}

-- Residuals are keyed by material ("item/name" or "fluid/name") and contain
-- optional prod/cons rates per second. Stock entries contain count and optional
-- per_min trend; missing stock means unknown, distinct from a known zero count.
-- Graph recipe names, rate recipe names and capacity keys share the same IDs.

---@param recipe_names string[]
---@param rates ProductionFlowRates Recipe rates indexed by recipe name.
---@param capacity table<string, number> Normal crafts per second by recipe.
---@param used table<string, boolean> Non-reversing recipes included in the model.
---@return number|nil utilisation Nil when no included positive capacity exists.
local function utilisation_of(recipe_names, rates, capacity, used)
  local completed, possible = 0, 0
  for _, recipe_name in ipairs(recipe_names) do
    if used[recipe_name] and capacity[recipe_name] and capacity[recipe_name] > 0 then
      local recipe_rate = rates.recipes[recipe_name]
      local normal_crafts = recipe_rate and recipe_rate.normal_cps or 0
      completed = completed + normal_crafts
      possible = possible + capacity[recipe_name]
    end
  end
  if possible <= 0 then return nil end
  return completed / possible
end

---@return table<string, boolean> used Recipe membership, excluding reversing recipes.
local function used_recipes(graph, model)
  local used = {}
  for _, recipe_name in ipairs(model.used) do
    local recipe = graph.recipes[recipe_name]
    if recipe and not recipe.reversing then used[recipe_name] = true end
  end
  return used
end

-- Copy membership without mutating model residuals; positive stock adds empty
-- residual entries so stored-only materials can become rows.
---@return table<string, table> residuals Original residual values or empty tables.
local function residuals_with_stock(model_residuals, stock)
  local residuals = {}
  for key, residual in pairs(model_residuals) do residuals[key] = residual end
  for key, entry in pairs(stock) do
    if entry.count > 0 and not residuals[key] then residuals[key] = {} end
  end
  return residuals
end

-- A completed stock scan supplies known zeros for items, never for fluids.
---@return ProductionFlowStockEntry|nil entry
local function stock_for(key, stock, known)
  local entry = stock[key]
  if not entry and known and key:sub(1, 5) == "item/" then entry = { count = 0 } end
  return entry
end

---@return string status A key in B.STATUS; precedence is significant.
local function status_for(reference, net_fraction, producer_utilisation, consumer_utilisation, stock)
  local status
  if reference <= 1e-3 then status = "stored"
  elseif net_fraction < -B.NET_TOL then status = "deficit"
  elseif net_fraction > B.NET_TOL then status = "surplus"
  elseif producer_utilisation == nil or consumer_utilisation == nil then
    status = (producer_utilisation == nil and consumer_utilisation == nil) and "source" or "ok"
  elseif consumer_utilisation < B.LOW and producer_utilisation >= B.HIGH then status = "limited"
  elseif consumer_utilisation < B.LOW and producer_utilisation < B.LOW then status = "starved"
  elseif producer_utilisation < B.LOW and consumer_utilisation >= B.HIGH then status = "overbuilt"
  else status = "ok" end
  -- A deficit without machine production or known stock is a source/sink.
  if status == "deficit" and producer_utilisation == nil and not stock then status = "source" end
  return status
end

---@return number|nil seconds Prefer a measured stock drain, then a negative net rate.
function B.time_to_empty(stock, net)
  if stock and stock.count > 0 then
    local drain = (stock.per_min and stock.per_min < 0) and (-stock.per_min / 60)
      or ((net < 0) and -net or 0)
    if drain > 0 then return stock.count / drain end
  end
end

-- Rows retain public abbreviated field names used by the Balance UI/exporters:
-- prod/cons/net are per-second rates, netp is net / max(prod, cons), pu/cu are
-- optional utilisation ratios, stock/trend are optional count/per-minute values,
-- and eta is optional seconds to empty. Unknown optional fields remain absent.
---@return table|nil row Nil for negligible throughput without positive stock.
local function material_row(key, residual, graph, model, capacity, used, stock, known)
  local produced, consumed = residual.prod or 0, residual.cons or 0
  local reference = math.max(produced, consumed)
  if reference > 1e-3 or (stock[key] and stock[key].count > 0) then
    local node = graph.nodes[key]
    local producer_utilisation = node and utilisation_of(node.producers, model.rates, capacity, used)
    local consumer_utilisation = node and utilisation_of(node.consumers, model.rates, capacity, used)
    local net = produced - consumed
    local net_fraction = reference > 0 and net / reference or 0
    local entry = stock_for(key, stock, known)
    return {
      key = key, prod = produced, cons = consumed, net = net, netp = net_fraction,
      pu = producer_utilisation, cu = consumer_utilisation,
      stock = entry and entry.count, trend = entry and entry.per_min,
      eta = B.time_to_empty(entry, net),
      status = status_for(reference, net_fraction, producer_utilisation, consumer_utilisation, entry),
    }
  end
end

local function row_before(a, b)
  local order_a, order_b = B.STATUS[a.status].order, B.STATUS[b.status].order
  if order_a ~= order_b then return order_a < order_b end
  local severity_a, severity_b = math.abs(a.netp), math.abs(b.netp)
  if severity_a ~= severity_b then return severity_a > severity_b end
  return a.key < b.key
end

local SORT_VALUES = {
  deficit = function(row) return row.net < 0 and row.net or math.huge end,
  empty = function(row) return row.eta or math.huge end,
}

-- Order an existing section by measurement, preserving its priority order for ties.
function B.sort(rows, order)
  local value = SORT_VALUES[order]
  if not value or #rows < 2 then return end
  local position = {}
  for i, row in ipairs(rows) do position[row] = i end
  table.sort(rows, function(a, b)
    local va, vb = value(a), value(b)
    if va ~= vb then return va < vb end
    return position[a] < position[b]
  end)
end

---@param sidx number|nil Surface index, passed through to the model and samplers.
---@param period number|nil Model sampling period, passed through unchanged.
---@return table[] rows Sorted by status, descending absolute netp, then material key.
---@return number seconds Model's measured window length.
---@return table<string, ProductionFlowStockEntry> stock Physical stock measurements.
---@return boolean known Whether items missing from stock can be treated as empty.
---@return table<string, table> totals Measured production and consumption rates per second.
function B.rows(sidx, period)
  local graph = Graph.get()
  local model = Model.build(sidx, period)
  local capacity = Sampler.capacity(sidx)
  local stock = Sampler.stock(sidx)
  local used = used_recipes(graph, model)
  local residuals = residuals_with_stock(model.residuals, stock)
  local known = Sampler.stock_known(sidx)
  local rows = {}
  for key, residual in pairs(residuals) do
    local row = material_row(key, residual, graph, model, capacity, used, stock, known)
    if row then rows[#rows + 1] = row end
  end
  table.sort(rows, row_before)
  return rows, model.seconds, stock, known, model.rates and model.rates.nodes or model.residuals
end

return B
