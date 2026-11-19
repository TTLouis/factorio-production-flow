local Loc = require("scripts.locale")
local Axis = {}

function Axis.add(parent, axis, tooltip)
  return parent.add { type = "switch", name = "axis", allow_none_state = false,
    switch_state = axis == "events" and "right" or "left",
    left_label_caption = Loc("transfer-axis-time"), right_label_caption = Loc("transfer-axis-events"),
    tooltip = tooltip, tags = { transfer_axis = true } }
end

function Axis.selection(element)
  if not (element and element.valid and element.tags.transfer_axis) then return nil end
  if element.switch_state == "right" then return "events" end
  if element.switch_state == "left" then return "time" end
end

return Axis
