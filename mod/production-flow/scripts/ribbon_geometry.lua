-- One route description for GUI sprites, polygons and offline diagnostics.
local S = require("shared.sprites")
local G = {}
function G.round(x) return math.floor(x + 0.5) end

function G.box(x, y, w, h)
  local x1, y1 = G.round(x), G.round(y)
  return x1, y1, G.round(x + w) - x1, G.round(y + h) - y1
end

-- Same cubic used by tools/gen_atlas.py; u is the curve parameter, not x.
function G.bezier(u)
  return 1.5 * u * (1 - u) + u ^ 3, u * u * (3 - 2 * u)
end

function G.rect(out, x, y, w, h)
  x, y, w, h = G.box(x, y, w, h)
  if w > 0 and h > 0 then out[#out + 1] = { kind = "bar", x = x, y = y, w = w, h = h } end
end

local function curve(out, xa, xb, ya, yb, t)
  xa, xb = G.round(xa), G.round(xb)
  local y0, y1 = G.round(ya), G.round(yb)
  local t0, t1 = G.round(ya + t) - y0, G.round(yb + t) - y1
  if xb <= xa or t0 <= 0 or t1 <= 0 then return end
  if y0 == y1 and t0 == t1 then return G.rect(out, xa, y0, xb - xa, t0) end
  -- Both backends use the same capped central curve and straight approaches.
  if xb - xa > S.CURVE_MAX then
    local c0 = G.round((xa + xb - S.CURVE_MAX) / 2)
    G.rect(out, xa, y0, c0 - xa, t0)
    G.rect(out, c0 + S.CURVE_MAX, y1, xb - c0 - S.CURVE_MAX, t1)
    xa, xb = c0, c0 + S.CURVE_MAX
  end
  local top = math.min(y0, y1)
  local h = math.max(y0 + t0, y1 + t1) - top
  out[#out + 1] = { kind = "curve", x = xa, y = top, w = xb - xa, h = h,
    ya = y0, yb = y1, t0 = t0, t1 = t1, dir = y1 >= y0 and "d" or "u",
    k = S.shape_index((t0 + t1) / (2 * h)), box_h = h }
end

local function elbow(out, corner, k, x, y, box)
  local w, h
  x, y, w, h = G.box(x, y, box, box)
  if w > 0 and h > 0 then
    out[#out + 1] = { kind = "elbow", corner = corner, k = k, x = x, y = y, w = w, h = h }
  end
end

function G.route(l, xa, xb, ya, yb)
  local out, t = {}, l.t
  if xb <= xa or t <= 0 then return out end
  local end_x = xb
  if l.route == "late" and l.curve_x0 then
    G.rect(out, xa, ya, l.curve_x0 - xa, t)
    xa = l.curve_x0
  elseif l.route == "early" and l.curve_x1 then xb = l.curve_x1 end
  if l.ortho and math.abs(xa - l.cx0) < 1 then
    local o = l.ortho
    local R, xv = o.R, o.xv
    local box = R + t
    G.rect(out, xa, ya, xv - R - xa, t)
    if yb > ya then
      elbow(out, "bl", o.k, xv - R, ya, box)
      G.rect(out, xv, ya + box, t, yb - R - ya - box)
      elbow(out, "tr", o.k, xv, yb - R, box)
    else
      elbow(out, "tl", o.k, xv - R, ya - R, box)
      G.rect(out, xv, yb + box, t, ya - R - yb - box)
      elbow(out, "br", o.k, xv, yb, box)
    end
    G.rect(out, xv + box, yb, xb - xv - box, t)
  else
    curve(out, xa, xb, ya, yb, t)
  end
  if xb < end_x then G.rect(out, xb, yb, end_x - xb, t) end
  return out
end

-- Vertices of an atlas elbow in its rounded box. Independent axis scales keep
-- polygon corners aligned with the GUI's edge rounding, even in a 1px rectangle.
function G.arc_points(p, steps)
  local q = S.steps.elbow_q[p.k]
  local left = p.corner == "bl" or p.corner == "tl"
  local bottom = p.corner == "bl" or p.corner == "br"
  local cx, cy = left and 0 or 1, bottom and 1 or 0
  local start = ({ bl = -math.pi / 2, tr = math.pi / 2, tl = 0, br = math.pi })[p.corner]
  local points = {}
  for i = 0, steps do
    local a = start + math.pi / 2 * i / steps
    for _, r in ipairs({ 1 - q, 1 }) do
      points[#points + 1] = { p.x + (cx + r * math.cos(a)) * p.w,
        p.y + (cy + r * math.sin(a)) * p.h }
    end
  end
  return points
end

-- One triangle strip for a complete routed ribbon. Degenerate triangles join
-- primitive strips without painting spurious diagonals between their endpoints.
function G.mesh(pieces)
  local out = {}
  for _, p in ipairs(pieces) do
    local v = {}
    if p.kind == "bar" then
      v = { { p.x, p.y }, { p.x, p.y + p.h }, { p.x + p.w, p.y }, { p.x + p.w, p.y + p.h } }
    elseif p.kind == "curve" then
      local steps = math.max(16, math.min(96, math.ceil(math.max(p.w, p.h) / 6)))
      for i = 0, steps do
        local x, e = G.bezier(i / steps)
        local y = p.ya + (p.yb - p.ya) * e
        v[#v + 1] = { p.x + p.w * x, y }
        v[#v + 1] = { p.x + p.w * x, y + p.t0 + (p.t1 - p.t0) * e }
      end
    else
      v = G.arc_points(p, math.max(12, math.min(64, math.ceil(math.max(p.w, p.h) / 4))))
    end
    if #out > 0 then out[#out + 1] = out[#out]; out[#out + 1] = v[1] end
    for _, point in ipairs(v) do out[#out + 1] = point end
  end
  return out
end

return G
