-- Balance tab: per item, is it in deficit (draining a buffer), in surplus (filling one),
-- held back by its supply, or over-built for its demand?
--
-- Inputs (all measured):
--   produced / consumed : force production statistics (window average)
--   machine utilisation : normal crafts / capacity (sum of crafting_speed / energy)
--   stock + trend       : logistic-network contents, sampled every 10 s over ~60 s

local Graph = require("scripts.graph")
local Model = require("scripts.model")
local Sampler = require("scripts.sampler")

local B = {}

B.NET_TOL = 0.05   -- |net| below 5 % of throughput counts as balanced
B.LOW = 0.85       -- machines below 85 % busy are "waiting"
B.HIGH = 0.95      -- machines above 95 % busy are "maxed"

B.STATUS = {
  deficit   = { order = 1, label = "Deficit",          color = "1,0.35,0.35",
                help = "Measured consumption exceeds production by more than 5%. Check stored supply and transport; logistic stock gives an estimated time to empty when a drain is measured." },
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

local function util_of(names, rates, cap, used)
  local done, possible = 0, 0
  for _, r in ipairs(names) do
    if used[r] and cap[r] and cap[r] > 0 then
      local rr = rates.recipes[r]
      local normal = 0
      if rr then normal = Sampler.PF_INCLUDES_BONUS and rr.cps / (1 + rr.prod) or rr.cps end
      done = done + normal
      possible = possible + cap[r]
    end
  end
  if possible <= 0 then return nil end
  return done / possible
end

function B.rows(sidx, period)
  local g = Graph.get()
  local m = Model.build(sidx, period)
  local cap = Sampler.capacity(sidx)
  local stock = Sampler.stock(sidx)
  local used = {}
  for _, r in ipairs(m.used) do
    local rec = g.recipes[r]
    if rec and not rec.reversing then used[r] = true end
  end

  local rows = {}
  for key, res in pairs(m.residuals) do
    local prod, cons = res.prod or 0, res.cons or 0
    local ref = math.max(prod, cons)
    if ref > 1e-3 then
      local nd = g.nodes[key]
      local pu = nd and util_of(nd.producers, m.rates, cap, used)
      local cu = nd and util_of(nd.consumers, m.rates, cap, used)
      local net = prod - cons
      local netp = net / ref
      local st = stock[key]
      local status
      if netp < -B.NET_TOL then status = "deficit"
      elseif netp > B.NET_TOL then status = "surplus"
      elseif pu == nil or cu == nil then status = (pu == nil and cu == nil) and "source" or "ok"
      elseif cu < B.LOW and pu >= B.HIGH then status = "limited"
      elseif cu < B.LOW and pu < B.LOW then status = "starved"
      elseif pu < B.LOW and cu >= B.HIGH then status = "overbuilt"
      else status = "ok" end
      -- a deficit with nothing producing it in a machine is just a sink being fed from mining / stock
      if status == "deficit" and pu == nil and not st then status = "source" end
      local eta
      if st and st.count > 0 then
        local drain = (st.per_min and st.per_min < 0) and (-st.per_min / 60) or ((net < 0) and -net or 0)
        if drain > 0 then eta = st.count / drain end
      end
      rows[#rows + 1] = { key = key, prod = prod, cons = cons, net = net, netp = netp, pu = pu, cu = cu,
                          stock = st and st.count, trend = st and st.per_min, eta = eta, status = status }
    end
  end
  table.sort(rows, function(a, b)
    local oa, ob = B.STATUS[a.status].order, B.STATUS[b.status].order
    if oa ~= ob then return oa < ob end
    local sa, sb = math.abs(a.netp), math.abs(b.netp)
    if sa ~= sb then return sa > sb end
    return a.key < b.key
  end)
  return rows, m.seconds
end

return B
