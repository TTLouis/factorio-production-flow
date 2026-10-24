-- Stable, player-local help; sampling and automatic refresh do not rebuild it.
local H={}
local NAME="ssk_help"
local topics={
  {name="Start here",sections={
    {"Open and inspect", "Open Production Flow with its flow-chart button at the top left. Balance compares items and fluids on the selected surface. Production and item/fluid selection do not require logistic storage. Use a row's magnifier to inspect its inputs and consumers. Expand inputs follows the chain upstream."},
    {"Periods and updates", "The default period is 10 minutes. Recent uses the shorter window from mod settings. Auto-update chart controls automatic chart redraws; sampling continues and Balance values keep updating when it is off."},
    {"A stable item list", "Rows stay in place while values change, so updates do not interrupt selection. List order held means filtering and sorting have not been reapplied. Update list reapplies them, including new, balanced or inactive materials. Items stored without recent production appear as Stock only under Everything."},
    {"Material names and recipes", "Chart nodes use item and fluid names. A Copper plate node can be made by smelting or casting; the Making line lists recipes recorded for the selected material. Simple recipes are drawn as connections; recipes with several outputs may have their own node."},
    {"Work in progress", "Balance is the main focus of this beta. Focus, Full Sankey and optional graph grouping need more polish. A category such as Vulcanus in the unfinished grouped view is not a recipe name or a production location."},
  }},
  {name="Numbers & stock",sections={
    {"History warm-up", "Recording begins when the mod is installed. History collected shows how much of your selected period is available. During warm-up, rates use the recorded time so far. Recorded history survives saving and loading; earlier recipe activity cannot be reconstructed."},
    {"Made, used and net", "Made and Used are measured changes in Factorio's production statistics divided by the recorded time. Net = Made - Used. Positive net means more was made than used during that period; negative net means more was used."},
    {"Selected-material consumption", "The Uses heading names the selected material. Every consumer rate underneath is consumption of that material, not the consumer's output. With Water selected, a Concrete node showing 18 fluid/s means it consumed 18 water/s."},
    {"Chest stock", "Stock reads physical contents of ordinary and logistic chests belonging to the player force on the selected surface. This includes requester and buffer chests, without needing a logistic network. All qualities are combined, once per chest. A dash means unavailable (including fluids or an unfinished first scan); zero means measured empty."},
    {"Sampling and scope", "Chest reads are spread across ticks. Only completed scans replace the previous result. After each complete scan, the sampler waits for the Chest stock scan interval in Mod settings / Map: default 5 minutes, minimum 1. Very large scans add to that interval. Balance shows the stock sample age; production rates still refresh every 5 seconds. Moving items between chests during a scan can affect a sample. Player and vehicle inventories, machine buffers, belts, ground items, linked/infinity chests and fluid tanks are excluded."},
    {"Stock changes and empty time", "Stock trend uses up to seven completed samples (about 30 minutes at the default interval, about 6 minutes at the minimum, longer for large scans), separately from the production period. Approximate empty time divides stored stock by its recent drain; a production deficit is used when no recent stock drain is measured. It assumes the drain continues. Physical chest counts do not subtract robot reservations and cannot become negative availability balances."},
  }},
  {name="Alerts & charts",sections={
    {"Alerts are hints", "Deficit and Surplus mean measured rates differ by more than 5% of the larger rate. Low activity means both producer and consumer utilisation are below 85%; it does not prove missing inputs. Possible supply limit compares waiting consumers with producers at least 95% busy. Spare capacity is also an estimate, not a confirmed cause."},
    {"Utilisation", "Estimated utilisation compares recorded normal crafts with current crafting capacity from machine speed and recipe time. Changing machines, recipes or modules can make historical utilisation exceed 100%. Check inputs, power, transport, output space and demand before treating an alert as a diagnosis."},
    {"Links versus totals", "Recipe links are estimated from completed crafts, ingredients, productivity and expected product yields. They can differ from production-statistic totals. Grey ends represent sources or uses outside the drawn connections, such as mining, fuel, labs or filtered activity."},
    {"Widths, colors and navigation", "Compressed widths use a square-root scale; Proportional uses rate-based widths. Fluids have a separate visual scale and thin flows have a minimum thickness. Widths across materials are not a mass balance. Colors can follow destinations or sources. Hover highlights connections; click to inspect or select, and Shift-click pins a Balance chain. Fit and Center help navigate; dense charts still scroll."},
    {"Scope and diagnostics", "Each view covers one surface. Interplanetary shipments and physical belt or pipe routes are not traced. Diagnostic exports are local files under script-output/production-flow. Automatic exports are optional and off by default for new installations."},
  }},
}
function H.close(player)
  local f=player.gui.screen[NAME]
  if f then f.destroy() end
end
function H.open(player)
  H.close(player)
  local res,scale=player.display_resolution,player.display_scale
  local W=math.min(900,math.floor(res.width/scale)-60)
  local height=math.min(740,math.floor(res.height/scale)-90)
  local f=player.gui.screen.add{type="frame",name=NAME,direction="vertical"}
  f.style.width,f.style.height=W,height
  local header=f.add{type="flow",direction="horizontal"}
  header.drag_target=f
  header.add{type="label",caption="Production Flow help",style="frame_title"}
  local drag=header.add{type="empty-widget",style="draggable_space_header"}
  drag.style.horizontally_stretchable=true;drag.style.height=24
  header.add{type="button",caption="Close",tags={ssk_ui="help_close"}}
  local tabs=f.add{type="tabbed-pane",name="ssk_help_tabs"}
  tabs.style.horizontally_stretchable=true;tabs.style.vertically_stretchable=true
  for i,topic in ipairs(topics) do
    local tab=tabs.add{type="tab",caption=topic.name}
    local scroll=tabs.add{type="scroll-pane",name="ssk_help_topic_"..i,
      horizontal_scroll_policy="never",vertical_scroll_policy="auto"}
    scroll.style.width=W-36;scroll.style.height=height-110
    local body=scroll.add{type="flow",direction="vertical"}
    body.style.vertical_spacing=10
    for _,section in ipairs(topic.sections) do
      local title=body.add{type="label",caption=section[1]}
      title.style.font="default-bold";title.style.font_color={0.95,0.85,0.65}
      local text=body.add{type="label",caption=section[2]}
      text.style.single_line=false;text.style.width=W-70
    end
    tabs.add_tab(tab,scroll)
  end
  f.auto_center=true
  -- Keep the main frame as the opened GUI. Switching player.opened here
  -- raises on_gui_closed for it and can close both windows in the engine.
  if f.bring_to_front then f.bring_to_front() end
  return f
end
return H
