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

local function surface()
  local s = game.get_surface(C.SURFACE)
  if s then return s end
  s = game.create_surface(C.SURFACE, {
    default_enable_all_autoplace_controls = false,
    autoplace_settings = {
      tile = { treat_missing_as_default = false, settings = {} },
      entity = { treat_missing_as_default = false, settings = {} },
      decorative = { treat_missing_as_default = false, settings = {} },
    },
    peaceful_mode = true, no_enemies_mode = true,
  })
  pcall(function() s.always_day = true end)
  pcall(function() s.freeze_daytime = true; s.daytime = 0 end)
  pcall(function() s.show_clouds = false end)
  for _, f in pairs(game.forces) do
    pcall(function() f.set_surface_hidden(s, true) end)
  end
  return s
end

-- make sure the drawing area exists, has plain tiles and is charted for the player's force
-- (a camera may not show uncharted areas)
local function prepare_area(player, s, x0, y0, x1, y1)
  storage.canvas_chunks = storage.canvas_chunks or {}
  local done = storage.canvas_chunks
  local cx0, cy0, cx1, cy1 = math.floor(x0 / 32), math.floor(y0 / 32), math.floor(x1 / 32), math.floor(y1 / 32)
  local new = {}
  for cx = cx0, cx1 do
    for cy = cy0, cy1 do
      local k = cx .. "," .. cy
      if not done[k] then
        new[#new + 1] = { cx, cy }
        s.request_to_generate_chunks({ cx * 32 + 16, cy * 32 + 16 }, 0)
      end
    end
  end
  if #new > 0 then
    s.force_generate_chunk_requests()
    for _, c in ipairs(new) do
      local tiles = {}
      for x = c[1] * 32, c[1] * 32 + 31 do
        for y = c[2] * 32, c[2] * 32 + 31 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end
      end
      pcall(function() s.set_tiles(tiles, false) end)
      done[c[1] .. "," .. c[2]] = true
    end
  end
  pcall(function() player.force.chart(s, { { x0, y0 }, { x1, y1 } }) end)
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

  function P.rect(x, y, w, h, color)
    x, y, w, h = Geometry.box(x, y, w, h)
    if w <= 0 or h <= 0 then return nil end
    return keep(rendering.draw_rectangle { surface = s, players = players, filled = true,
      left_top = wp(x, y), right_bottom = wp(x + w, y + h), color = color })
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
    local vertices = {}
    for _, point in ipairs(Geometry.mesh(pieces)) do vertices[#vertices + 1] = wp(point[1], point[2]) end
    if #vertices < 3 then return nil end
    return keep(rendering.draw_polygon { surface = s, players = players, vertices = vertices, color = color })
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
function C.camera_spec(player, P)
  return {
    type = "camera",
    position = { P.ox + P.W * PX / 2, P.oy + P.H * PX / 2 },
    surface_index = P.surface.index,
    zoom = player.display_scale,
  }
end

return C
