-- Immediate materials -> selected item -> uses, for the Balance inspector.
local N = {}
N.MAX_DEPTH = 6 -- room for enrichment, molten metal and ingots in modded chains

function N.build(nodes, links, model, focus, depth)
  depth = math.max(1, math.min(N.MAX_DEPTH, depth or 1))
  local nn, nl = {}, {}
  local function copy(key, distance)
    local alias = distance == 0 and key or key .. (distance == -1 and "#use"
      or distance == 1 and "#input" or "#input" .. distance)
    if nn[alias] then return nn[alias] end
    local original, out = nodes[key], {}
    if original then for k, v in pairs(original) do out[k] = v end end
    local rates = model.residuals[key] or {}
    out.key, out.kind, out.group_key = alias, key:match("^(%a+)/"), key
    out.prod, out.cons = rates.prod or out.prod or 0, rates.cons or out.cons or 0
    out.loops, out.contrib, out.neighborhood_tier = {}, {}, depth - distance
    nn[alias] = out
    return out
  end
  local function link(from, to, rate, note)
    if rate <= 1e-4 then return end
    local id = from.key .. ">" .. to.key
    if not nl[id] then nl[id] = { from = from.key, to = to.key, rate = 0, note = note } end
    nl[id].rate = nl[id].rate + rate
  end
  local visited = {}
  local function inputs(key, distance)
    local target = copy(key, distance)
    if distance >= depth or visited[target.key] then return target end
    visited[target.key] = true
    local via_map = {}
    for _, l in pairs(links) do
      if l.to == key then
        local via = {}
        if nodes[l.from].kind == "recipe" then
          for _, ingredient in pairs(links) do
            if ingredient.to == l.from then
              local input = inputs(ingredient.from, distance + 1)
              link(input, target, ingredient.rate, "Full input to the producing recipe; shared co-products are not allocated.")
              via[#via + 1] = input.key
            end
          end
        else
          local input = inputs(l.from, distance + 1)
          link(input, target, l.rate)
          via[#via + 1] = input.key
        end
        via_map[l.from] = via
      end
    end
    for _, contribution in ipairs(nodes[key] and nodes[key].contrib or {}) do
      local via = {}
      for _, source in ipairs(contribution.via) do
        for _, alias in ipairs(via_map[source] or {}) do via[#via + 1] = alias end
      end
      target.contrib[#target.contrib + 1] = { rate = contribution.rate, via = via }
    end
    return target
  end
  local center = inputs(focus, 0)
  for _, l in pairs(links) do
    if l.from == focus then
      local use = copy(l.to, -1)
      link(center, use, l.rate)
      use.selected_usage = (use.selected_usage or 0) + l.rate
      use.selected_material = focus
      if use.kind == "recipe" then
        local outputs = {}
        for _, product in pairs(links) do
          if product.from == l.to then outputs[#outputs + 1] = product.to end
        end
        table.sort(outputs)
        use.context = "Used by this multi-output recipe. Products: " .. table.concat(outputs, ", ")
      end
    end
  end
  return nn, nl
end

function N.layout(L, us, W, viewH, V)
  local top = V.PAD_TOP + 16 -- Reserve both lines of the selected-material Uses heading.
  local available = math.max(100, viewH - top - V.PAD_BOTTOM)
  -- Solve against complete node/port/header bounds, including minimum ribbons.
  -- Fixed icon and text sizes are the lower bound; oversized graphs scroll.
  local function packed(scale)
    local highest = 0
    for _, col in ipairs(L.cols) do
      local height = 0
      for _, n in ipairs(col) do
        local tin = n.w_stub_in > 0 and math.max(L.min_t, n.w_stub_in*scale) or 0
        local tout = n.w_stub_out > 0 and math.max(L.min_t, n.w_stub_out*scale) or 0
        for _, l in ipairs(n.ins) do tin=tin+math.max(L.min_t,l.w*scale) end
        for _, l in ipairs(n.outs) do tout=tout+math.max(L.min_t,l.w*scale) end
        height=height+V.NODE_HEAD+math.max(V.F_BAR_MIN,n.wvalue*scale,tin,tout)+V.F_GAP
      end
      highest=math.max(highest,height-V.F_GAP)
    end
    return highest
  end
  local max_weight = 0
  for _, n in pairs(L.nodes) do max_weight=math.max(max_weight,n.wvalue) end
  local lo, hi = 0, max_weight > 0 and 140/max_weight or 1
  local target = math.max(available, packed(0))
  for _=1,32 do
    local mid=(lo+hi)/2
    if packed(mid)<=target+0.01 then lo=mid else hi=mid end
  end
  L.fit = lo
  L.scale = us.keep_layout and us.layout_snapshot.scale or lo*(us.zoom or 1)
  for _, l in ipairs(L.links) do l.t = math.max(L.min_t, l.w * L.scale) end
  local heights, H = {}, available
  for ci, col in ipairs(L.cols) do
    table.sort(col, function(a, b)
      local pa, pb = (us.auto_rank or {})[a.key], (us.auto_rank or {})[b.key]
      if pa and pb and pa ~= pb then return pa < pb end
      return a.key < b.key
    end)
    local h = 0
    for _, n in ipairs(col) do
      local tin = n.w_stub_in > 0 and math.max(L.min_t, n.w_stub_in * L.scale) or 0
      local tout = n.w_stub_out > 0 and math.max(L.min_t, n.w_stub_out * L.scale) or 0
      n.t_stub_in, n.t_stub_out = tin, tout
      for _, l in ipairs(n.ins) do tin = tin + l.t end
      for _, l in ipairs(n.outs) do tout = tout + l.t end
      n.tin, n.tout = tin, tout
      n.h = math.max(V.F_BAR_MIN, n.wvalue * L.scale, tin, tout)
      n.icon_above, n.slot = true, V.NODE_HEAD + n.h
      h = h + n.slot + V.F_GAP
    end
    heights[ci] = math.max(0, h - V.F_GAP)
    H = math.max(H, heights[ci])
  end
  if us.keep_layout and us.layout_snapshot.content_h then
    H=math.max(H,us.layout_snapshot.content_h-top-V.PAD_BOTTOM)
  end
  local right_label = math.min(148, math.max(80, math.floor(W * 0.22)))
  L.center_ci = L.nodes[us.focus].ci
  L.col_x = { 24, math.floor(W / 2 - V.NODE_W / 2), W - right_label - 12 }
  if #L.cols > 3 then
    W = math.max(W, (#L.cols - 1) * (V.HEADER_W + 48) + V.HEADER_W + 24)
    L.col_x = {}
    for ci = 1, #L.cols do L.col_x[ci] = 24 + (ci - 1) * (W - V.HEADER_W - 24) / (#L.cols - 1) end
  end
  L.label_above, L.label_w = true, {}
  for ci, col in ipairs(L.cols) do
    local y = top + (H - heights[ci]) / 2
    if us.keep_layout then y=top end
    L.label_w[ci] = ci < #L.cols and math.min(V.HEADER_W - 8, L.col_x[ci + 1] - L.col_x[ci] - 8) or right_label
    for _, n in ipairs(col) do
      if us.keep_layout and us.layout_snapshot.tops[n.key] then
        y=math.max(y,us.layout_snapshot.tops[n.key])
      end
      n.x, n.top, n.y = L.col_x[ci], y, y + V.NODE_HEAD
      H=math.max(H,n.top+n.slot-top)
      y = y + n.slot + V.F_GAP
    end
  end
  for _, col in ipairs(L.cols) do
    for _, n in ipairs(col) do
      table.sort(n.ins, function(a, b) return a.a.y < b.a.y end)
      table.sort(n.outs, function(a, b) return a.b.y < b.b.y end)
      local off = (n.h - n.tin) / 2
      for _, l in ipairs(n.ins) do l.y2 = n.y + off; off = off + l.t end
      n.stub_in_y = n.y + off
      off = (n.h - n.tout) / 2
      for _, l in ipairs(n.outs) do l.y1 = n.y + off; off = off + l.t end
      n.stub_out_y = n.y + off
    end
  end
  V.route(L, us); V.assign_colors(L, us)
  if #L.cols > 3 then
    for _, l in ipairs(L.links) do
      l.route, l.curve_x0, l.cx0, l.cx1, l.ortho = "late", l.a.x + V.HEADER_W, l.a.x + V.HEADER_W, l.b.x, nil
    end
  end
  us.auto_rank = {}
  for _, n in pairs(L.nodes) do us.auto_rank[n.key] = n.top end
  L.order, L.lane_order, L.sub_order, L.lane_list = {}, {}, {}, {}
  L.content_w, L.content_h, L.H, L.clamped = W, math.ceil(top + H + V.PAD_BOTTOM), H, 0
end

return N
