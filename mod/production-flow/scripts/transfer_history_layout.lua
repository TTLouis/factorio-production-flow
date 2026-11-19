local Layout = { STRIP_HEIGHT = 38, ROW_HEIGHT = 32, GAP = 4, SCROLL_GUTTER = 20 }

function Layout.strip(parent, name)
  local frame = parent.add { type = "frame", name = name, style = "subheader_frame", direction = "horizontal" }
  frame.style.height, frame.style.padding = Layout.STRIP_HEIGHT, 0
  frame.style.left_padding, frame.style.right_padding = 8, 8
  frame.style.horizontally_stretchable, frame.style.vertical_align = true, "center"
  return frame
end

function Layout.columns(parent, name, width)
  local frame = parent.add { type = "frame", name = name, style = "repeated_subheader_frame", direction = "horizontal" }
  frame.style.width, frame.style.height, frame.style.padding = width, Layout.ROW_HEIGHT, 0
  frame.style.vertical_align = "center"
  return frame
end

function Layout.plot_height(height)
  return math.max(130, math.min(228, math.floor(height * 0.34)))
end

function Layout.log_height(height, chart_height, note_height, external_title)
  local strips = external_title and 1 or 2
  local gaps = strips + 2 + (note_height > 0 and 1 or 0)
  return math.max(70, height - chart_height - note_height - strips * Layout.STRIP_HEIGHT - Layout.ROW_HEIGHT - gaps * Layout.GAP)
end

return Layout
