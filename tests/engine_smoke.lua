-- Injected only into the isolated test copy, never into the release.
local Geometry = require("scripts.ribbon_geometry")
local Smoke = {}
function Smoke.run(UI, Canvas)
  local surface = game.surfaces[1]
  local original = rendering
  local bad = pcall(function()
    original.draw_polygon { surface = surface, color = { 1, 0, 0 },
      vertices = { { target = { 0, 0 } }, { target = { 1, 0 } }, { target = { 1, 1 } } } }
  end)
  assert(not bad, "Engine must reject the previous crashing vertex format")
  -- --create has no connected player. Remove player visibility filters while
  -- retaining the actual engine implementations and all shape arguments.
  rendering = {
    draw_rectangle = function(a) a.players = nil; return original.draw_rectangle(a) end,
    draw_polygon = function(a) a.players = nil; return original.draw_polygon(a) end,
  }
  local player = { index = 1, force = game.forces.player }
  local painter = Canvas.begin(player, 640, 480)
  for _, t in ipairs({ 1, 6, 120.7 }) do
    for _, delta in ipairs({ -150, 0, 150 }) do
      for _, primitive in ipairs(Geometry.route({ t = t }, 30, 600, 200, 200 + delta)) do
        local object = painter.primitive(primitive, Canvas.col(1))
        assert(object and object.valid, "Engine rejected ribbon primitive")
      end
    end
  end
  for _, corner in ipairs({ "bl", "tr", "tl", "br" }) do
    assert(painter.primitive({ kind = "elbow", corner = corner, k = 16, x = 100, y = 100, w = 40, h = 40 }, Canvas.col(2)).valid)
  end
  local pieces = Geometry.route({ t = 13 }, 30, 600, 200, 100)
  for _, p in ipairs(Geometry.route({ t = 13 }, 600, 1000, 100, 300)) do pieces[#pieces + 1] = p end
  assert(painter.ribbon(pieces, Canvas.col(1)).valid, "Engine rejected complete ribbon mesh")
  Canvas.clear(1)
  rendering = original
  for _, size in ipairs({ { 1920, 1080 }, { 1366, 768 }, { 1280, 720 } }) do
    local w, h = UI.dimensions({ width = size[1], height = size[2] }, 1)
    assert(w < size[1] and h < size[2], "Frame exceeds 16:9 screen")
  end
  log("PRODUCTION FLOW ENGINE SMOKE OK: old crash reproduced; curves, rectangles and all elbows accepted")
end
return Smoke
