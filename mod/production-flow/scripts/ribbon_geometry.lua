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

function G.rect(out, x, y, w, h, vertical)
  x, y, w, h = G.box(x, y, w, h)
  if w > 0 and h > 0 then out[#out + 1] = { kind = "bar", x = x, y = y, w = w, h = h, vertical = vertical } end
end

function G.curve_width(drop, thickness, metro)
  if metro then return drop / 0.3 end
  -- At the cubic's midpoint, thickness across the bend is the
  -- vertical thickness divided by sqrt(1 + slope^2). Thick ribbons can
  -- tolerate a steeper curve while still showing at least 6 layout pixels.
  local max_slope = math.sqrt(math.max(1.3 ^ 2, (thickness / 6) ^ 2 - 1))
  return 2 * drop / max_slope
end

function G.steep(width, drop, thickness, metro)
  -- The cubic's midpoint slope is 2 * drop / width. Use the width of the
  -- actual bend, since long curves have straight approaches at both ends.
  return width > 0 and G.curve_width(drop, thickness, metro) > math.min(width, S.CURVE_MAX)
end

function G.bend(thickness, drop, width)
  local max_radius = (math.min(drop - 2, width - 4) - thickness) / 2
  if max_radius <= 0 then return end
  local k = S.elbow_index(math.min(0.7, thickness / (thickness + math.max(8, thickness * 0.6))))
  for i = k, #S.steps.elbow_q do
    local q = S.steps.elbow_q[i]
    local radius = thickness * (1 - q) / q
    if radius <= max_radius then return { k = i, R = radius } end
  end
end

-- Factorio truncates a widget's scaled size and offset separately. Round up
-- only at a connected edge that would otherwise stop a device pixel short.
function G.sprite_span(start, length, scale)
  if math.floor(start * scale) + math.floor(length * scale) < math.floor((start + length) * scale) then
    return length + 1
  end
  return length
end

function G.sprite_size(piece, scale)
  local w, h = piece.w, piece.h
  local corner = piece.corner
  if piece.kind == "curve" or (piece.kind == "bar" and not piece.vertical) or corner == "tr" or corner == "br" then
    w = G.sprite_span(piece.x, w, scale)
  end
  if piece.vertical or corner == "bl" or corner == "br" then
    h = G.sprite_span(piece.y, h, scale)
  end
  return w, h
end

-- Transform the completed route so zoom never runs the routing algorithm at
-- a different scale. Round shared endpoints together in viewport coordinates.
function G.scaled_piece(piece, scale)
  if scale == 1 then return piece end
  local q = {}
  for key, value in pairs(piece) do q[key] = value end
  q.x, q.y, q.w, q.h = G.box(piece.x * scale, piece.y * scale, piece.w * scale, piece.h * scale)
  q.w, q.h = math.max(1, q.w), math.max(1, q.h)
  if q.kind == "curve" then
    q.ya, q.yb = G.round(piece.ya * scale), G.round(piece.yb * scale)
    q.t0 = math.max(1, G.round((piece.ya + piece.t0) * scale) - q.ya)
    q.t1 = math.max(1, G.round((piece.yb + piece.t1) * scale) - q.yb)
    q.h = math.max(q.ya + q.t0, q.yb + q.t1) - q.y
    q.box_h = q.h
    q.k = S.shape_index((q.t0 + q.t1) / (2 * q.h))
  end
  return q
end

local function curve(out, xa, xb, ya, yb, t)
  xa, xb = G.round(xa), G.round(xb)
  local y0, y1 = G.round(ya), G.round(yb)
  local t0, t1 = G.round(ya + t) - y0, G.round(yb + t) - y1
  if xb <= xa or t0 <= 0 or t1 <= 0 then return end
  if y0 == y1 and t0 == t1 then return G.rect(out, xa, y0, xb - xa, t0) end
  -- Both backends use the same capped central curve and straight approaches.
  local end_x = xb
  if xb - xa > S.CURVE_MAX then
    local c0 = G.round((xa + xb - S.CURVE_MAX) / 2)
    G.rect(out, xa, y0, c0 - xa, t0)
    xa, xb = c0, c0 + S.CURVE_MAX
  end
  local top = math.min(y0, y1)
  local h = math.max(y0 + t0, y1 + t1) - top
  out[#out + 1] = { kind = "curve", x = xa, y = top, w = xb - xa, h = h,
    ya = y0, yb = y1, t0 = t0, t1 = t1, dir = y1 >= y0 and "d" or "u",
    k = S.shape_index((t0 + t1) / (2 * h)), box_h = h }
  G.rect(out, xb, y1, end_x - xb, t1)
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
      G.rect(out, xv, ya + box, t, yb - R - ya - box, true)
      elbow(out, "tr", o.k, xv, yb - R, box)
    else
      elbow(out, "tl", o.k, xv - R, ya - R, box)
      G.rect(out, xv, yb + box, t, ya - R - yb - box, true)
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

-- Approximate the rendered shape with narrow GUI rectangles. A whole curve's
-- bounding box would intercept nearby ribbons across the space between them.
function G.hover_regions(pieces, visit)
  local function area(left, top, right, bottom)
    local y = math.max(0, top - math.max(0, (4 - (bottom - top)) / 2))
    local x, yy, w, h = G.box(left, y, right - left, math.max(4, bottom - top))
    if w > 0 and h > 0 then visit(x, yy, w, h) end
  end
  for _, p in ipairs(pieces) do
    if p.kind == "bar" then
      area(p.x, p.y, p.x + p.w, p.y + p.h)
    elseif p.kind == "curve" then
      local steps = math.max(2, math.min(12, math.ceil(math.max(p.w, p.h) / 40)))
      local x, y, thickness = p.x, p.ya, p.t0
      for i = 1, steps do
        local u = i / steps
        local bx, by = G.bezier(u)
        if p.linear then bx, by = u, u end
        local next_x, next_y = p.x + p.w * bx, p.ya + (p.yb - p.ya) * by
        local next_t = p.t0 + (p.t1 - p.t0) * by
        area(x, math.min(y, next_y), next_x, math.max(y + thickness, next_y + next_t))
        x, y, thickness = next_x, next_y, next_t
      end
    else
      local points = G.arc_points(p, 4)
      for i = 1, #points - 2, 2 do
        local a, b, c, d = points[i], points[i + 1], points[i + 2], points[i + 3]
        area(math.min(a[1], b[1], c[1], d[1]), math.min(a[2], b[2], c[2], d[2]),
          math.max(a[1], b[1], c[1], d[1]), math.max(a[2], b[2], c[2], d[2]))
      end
    end
  end
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
