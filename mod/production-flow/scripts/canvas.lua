-- Polygon renderer (experimental): draws the Sankey geometry with LuaRendering on a hidden
-- surface and shows it through a camera GUI element. Same layout as the sprite renderer;
-- icons, labels and buttons stay ordinary GUI elements placed on top of the camera.
--
--   1 layout px = 1/32 tile; camera zoom = display_scale  =>  1 layout px = 1 GUI px.
--   Each player draws in its own region of the surface; objects are visible only to them.

local palette = require("shared.palette")
local Geometry = require("scripts.ribbon_geometry")

local C = {}
C.SURFACE = "ssk-canvas"
local PX = 1 / 32
local REGION = 512 -- tiles between player regions (one region = 16k px wide)
-- The engine returns this limit when unlimited (zero) dimensions are assigned.
local MAP_LIMIT = 2000000

local function surface()
  local s = game.get_surface(C.SURFACE)
  if not s then
    s = game.create_surface(C.SURFACE, {
      width = 0, height = 0,
      default_enable_all_autoplace_controls = false,
      autoplace_settings = {
        tile = { treat_missing_as_default = false, settings = {} },
        entity = { treat_missing_as_default = false, settings = {} },
        decorative = { treat_missing_as_default = false, settings = {} },
      },
      peaceful_mode = true, no_enemies_mode = true,
    })
    for _, force in pairs(game.forces) do
      pcall(function() force.set_surface_hidden(s, true) end)
    end
  else
    -- Older canvases inherited finite dimensions from the save. Player regions
    -- start at x=512, so those bounds can prevent their chunks from generating.
    local settings = s.map_gen_settings
    if (settings.width > 0 and settings.width < MAP_LIMIT) or
        (settings.height > 0 and settings.height < MAP_LIMIT) then
      settings.width, settings.height = 0, 0
      s.map_gen_settings = settings
    end
  end
  if not s.generate_with_lab_tiles then
    s.generate_with_lab_tiles = true
    s.always_day = true
    s.freeze_daytime = true
    s.daytime = 0
    s.show_clouds = false
  end
  return s
end

-- make sure the drawing area exists, has plain tiles and is charted for the player's force
-- (a camera may not show uncharted areas)
local function prepare_area(player, s, x0, y0, x1, y1)
  local cx0, cy0, cx1, cy1 = math.floor(x0 / 32), math.floor(y0 / 32), math.floor(x1 / 32), math.floor(y1 / 32)
  local generation_requested = false
  for cx = cx0, cx1 do
    for cy = cy0, cy1 do
      if not s.is_chunk_generated({ cx, cy }) then
        s.request_to_generate_chunks({ cx * 32 + 16, cy * 32 + 16 }, 0)
        generation_requested = true
      end
    end
  end
  if generation_requested then s.force_generate_chunk_requests() end
  -- Match the complete generated chunks, including the camera's edge chunks.
  -- A partial-area chart request can leave saved-map cameras behind fog even
  -- though their player-filtered rendering objects already exist.
  pcall(function() player.force.chart(s, { { cx0 * 32, cy0 * 32 }, { (cx1 + 1) * 32, (cy1 + 1) * 32 } }) end)
end
C.surface = surface

function C.on_force_created(force)
  local s = game.get_surface(C.SURFACE)
  if s then pcall(function() force.set_surface_hidden(s, true) end) end
end

local function state(pi)
  storage.canvas = storage.canvas or {}
  local st = storage.canvas[pi]
  if not st then st = { objs = {} }; storage.canvas[pi] = st end
  return st
end

function C.clear(pi)
  local st = state(pi)
  for _, o in pairs(st.objs) do if o.valid then o.destroy() end end
  st.objs = {}
end

-- premultiplied colour (LuaRendering blends premultiplied); alpha defaults per palette entry
function C.col(i, a) return palette.tint(i, a) end

-- begin a drawing for player pi; returns a painter with px-space primitives
function C.begin(player, W, H)
  local pi = player.index
  C.clear(pi)
  local s = surface()
  local st = state(pi)
  local ox, oy = pi * REGION, 0
  prepare_area(player, s, ox - 4, oy - 4, ox + W * PX + 4, oy + H * PX + 4)
  local P = { surface = s, ox = ox, oy = oy, W = W, H = H }
  local players = { pi }
  local function keep(o) st.objs[#st.objs + 1] = o; return o end
  local function wp(x, y) return { ox + x * PX, oy + y * PX } end

  -- background (also defines what the camera shows outside the drawing)
  keep(rendering.draw_rectangle { surface = s, players = players, filled = true,
    left_top = wp(-64, -64), right_bottom = wp(W + 64, H + 64), color = { r = 0.16, g = 0.16, b = 0.17, a = 1 } })

  function P.rect(x, y, w, h, color, existing)
    x, y, w, h = Geometry.box(x, y, w, h)
    if w <= 0 or h <= 0 then return nil end
    local left_top, right_bottom = wp(x, y), wp(x + w, y + h)
    if existing then
      existing.left_top, existing.right_bottom = left_top, right_bottom
      return existing
    end
    return keep(rendering.draw_rectangle { surface = s, players = players, filled = true,
      left_top = left_top, right_bottom = right_bottom, color = color })
  end

  function P.line(x1, y1, x2, y2, color, width, dashed, offset)
    return keep(rendering.draw_line { surface = s, players = players, color = color, width = width,
      from = wp(x1, y1), to = wp(x2, y2), gap_length = dashed and 3 * PX or 0,
      dash_length = dashed and 5 * PX or 0, dash_offset = dashed and (offset or 0) * PX or 0 })
  end

  function P.text(x, y, caption, color, alignment, font)
    return keep(rendering.draw_text { surface = s, players = players, color = color,
      text = caption, target = wp(x, y), font = font or "default-small",
      alignment = alignment, vertical_alignment = "middle" })
  end

  function P.polygon(points, color)
    if #points < 3 then return nil end
    local vertices = {}
    for i, point in ipairs(points) do vertices[i] = wp(point[1], point[2]) end
    return keep(rendering.draw_polygon { surface = s, players = players, vertices = vertices, color = color })
  end

  -- S-curve ribbon from (xa, ya) to (xb, yb), constant vertical thickness t.
  -- Triangle strip: top/bottom edge points interleaved.
  function P.curve(xa, xb, ya, yb, t, color, t1)
    local w = xb - xa
    if w <= 0 then return nil end
    local n = math.max(16, math.min(96, math.ceil(math.max(w, math.abs(yb - ya)) / 6)))
    local v = {}
    for i = 0, n do
      local u = i / n
      local bx, e = Geometry.bezier(u)
      local x = xa + w * bx
      local y = ya + (yb - ya) * e
      v[#v + 1] = wp(x, y)
      v[#v + 1] = wp(x, y + t + ((t1 or t) - t) * e)
    end
    return keep(rendering.draw_polygon { surface = s, players = players, vertices = v, color = color })
  end

  function P.objects() return st.objs end
  function P.ribbon(pieces, color)
    return P.polygon(Geometry.mesh(pieces), color)
  end
  function P.primitive(p, color)
    if p.kind == "bar" then return P.rect(p.x, p.y, p.w, p.h, color) end
    if p.kind == "curve" then return P.curve(p.x, p.x + p.w, p.ya, p.yb, p.t0, color, p.t1) end
    local vertices = {}
    for _, point in ipairs(Geometry.arc_points(p, math.max(12, math.min(64, math.ceil(math.max(p.w, p.h) / 4))))) do
      vertices[#vertices + 1] = wp(point[1], point[2])
    end
    return keep(rendering.draw_polygon { surface = s, players = players, vertices = vertices, color = color })
  end
  return P
end

-- camera element sized to the drawing, top-left at layout (0, 0)
function C.camera_spec(player, P, top, height)
  return {
    type = "camera",
    position = { P.ox + P.W * PX / 2, P.oy + ((top or 0) + (height or P.H) / 2) * PX },
    surface_index = P.surface.index,
    zoom = player.display_scale,
  }
end

return C
