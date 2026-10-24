-- Naming + shape selection for ribbon sprites. Shared by data and control stage.
local steps = require("shared.ribbon_steps")

local S = {}
S.steps = steps
S.DIRS = { "d", "u" }   -- d = descending left->right, u = ascending

local log_ratio = math.log(steps.ratio)

function S.name(dir, k, color)
  return string.format("ssk-rib-%s-%02d-c%02d", dir, k, color)
end

-- nearest shape index (1-based) for thickness ratio r = t / box_height
function S.shape_index(r)
  if r >= 1 then return steps.count end
  if r <= steps.rmin then return 1 end
  local k = math.floor(math.log(r / steps.rmin) / log_ratio + 0.5) + 1
  if k < 1 then k = 1 elseif k > steps.count then k = steps.count end
  return k
end

-- one wide shape set; curves are capped in width by the renderer (S.CURVE_MAX) so they are
-- never stretched much horizontally
S.CURVE_MAX = math.floor(steps.cell_w * 1.05)
function S.pick(dir, k, color, box_h)
  return S.name(dir, k, color)
end

function S.elbow_name(corner, k, color)
  return string.format("ssk-elb-%s-%02d-c%02d", corner, k, color)
end

-- nearest elbow shape for thickness ratio q = t / (R + t); returns k and the exact q_k
function S.elbow_index(q)
  local best, bd = 1, math.huge
  for k, v in ipairs(steps.elbow_q) do
    local d = math.abs(v - q)
    if d < bd then best, bd = k, d end
  end
  return best, steps.elbow_q[best]
end

-- full rectangle sprite (used for node bars and straight segments)
function S.bar(color)
  return S.name("d", steps.count, color)
end

return S
