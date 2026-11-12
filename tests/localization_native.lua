-- Injected into private native tests; never packaged with the mod.
local resolve = require("scripts.test_locale_target")
local language = require("scripts.test_locale_language")
local probes = require("scripts.test_locale_probes")
local N, pending, remaining, started = {}, {}, 0, false

function N.start(player)
  if started then return end
  assert(player.locale == language, "Native test language mismatch: " .. player.locale .. " / " .. language)
  started = true
  for i, id in ipairs(player.request_translations(probes)) do
    if not pending[id] then remaining = remaining + 1 end
    pending[id] = { expected = resolve(probes[i]), key = probes[i][1] }
  end
  assert(remaining > 0, "No native locale probes requested")
end

function N.on_translated(event)
  local probe = pending[event.id]
  if not probe then return end
  assert(event.translated, "Native translation failed: " .. probe.key)
  assert(event.result == probe.expected, "Native locale mismatch: " .. probe.key
    .. "; expected " .. probe.expected .. "; received " .. event.result)
  pending[event.id] = nil
  remaining = remaining - 1
  if remaining == 0 then log("LOCALIZATION NATIVE PASS: " .. #probes .. " messages and plural cases; language=" .. language) end
end

function N.ready() return started and remaining == 0 end
return N
