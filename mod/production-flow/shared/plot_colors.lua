-- Existing plot colours, also used to tint GUI rectangles outside world-camera
-- postprocessing (notably modded night vision).
return {
  background={r=.16,g=.16,b=.17,a=1}, grid={r=.34,g=.34,b=.35,a=1},
  incoming={r=.40,g=.67,b=.90,a=1}, outgoing={r=.92,g=.58,b=.30,a=1},
  inbound_estimate={r=.33,g=.75,b=.69,a=1}, inbound_dispatch={r=.56,g=.62,b=.70,a=1},
  flow_in={r=.28,g=.59,b=.64,a=1}, flow_out={r=.80,g=.53,b=.29,a=1},
  -- Transfers ribbons (shared/ribbon_shades.lua): base, light, deep, fourth shade.
  ribbon_in_1={r=.28,g=.59,b=.73,a=1}, ribbon_in_2={r=.48,g=.75,b=.89,a=1},
  ribbon_in_3={r=.21,g=.43,b=.67,a=1}, ribbon_in_4={r=.35,g=.66,b=.65,a=1},
  ribbon_out_1={r=.80,g=.53,b=.29,a=1}, ribbon_out_2={r=.93,g=.70,b=.44,a=1},
  ribbon_out_3={r=.67,g=.38,b=.19,a=1}, ribbon_out_4={r=.86,g=.63,b=.23,a=1},
  ribbon_made={r=.55,g=.82,b=.65,a=1},
  -- SE Flow grouped by Items: one colour per top-8 item. These are the muted
  -- Sankey colours 4,5,1,11,3,6,10,13 (shared/palette.lua), so night-vision
  -- curves reuse the existing Sankey sprites; anything else is the grey band.
  ribbon_item_1={r=106/255,g=135/255,b=220/255,a=1}, ribbon_item_2={r=214/255,g=139/255,b=86/255,a=1},
  ribbon_item_3={r=204/255,g=71/255,b=103/255,a=1}, ribbon_item_4={r=75/255,g=172/255,b=164/255,a=1},
  ribbon_item_5={r=220/255,g=201/255,b=71/255,a=1}, ribbon_item_6={r=170/255,g=114/255,b=200/255,a=1},
  ribbon_item_7={r=217/255,g=178/255,b=178/255,a=1}, ribbon_item_8={r=179/255,g=138/255,b=96/255,a=1},
  ribbon_item_other={r=128/255,g=133/255,b=140/255,a=1},
  selected={r=.28,g=.24,b=.18,a=.35},
  measured={r=181/255,g=203/255,b=222/255,a=1},
  estimated={r=67/255,g=106/255,b=126/255,a=1},
  outline={r=82/255,g=97/255,b=109/255,a=1},
  receipt={r=139/255,g=212/255,b=156/255,a=1},
  history_grid={.25,.25,.26,1}, history_axis={.56,.54,.52,1},
  history_made={112/255,224/255,164/255,1}, history_used={1,79/255,89/255,1},
  history_surplus={100/255,245/255,114/255,1},
  history_use_one={202/255,131/255,84/255,1}, history_use_two={191/255,160/255,90/255,1},
  history_use_three={157/255,92/255,89/255,1}, history_other={99/255,112/255,130/255,1},
  history_hover={.15,.12,.06,.24},
  platform_loaded={.28,.59,.73,1}, platform_made={.55,.82,.65,1},
  platform_axis={.49,.48,.46,1}, platform_tick={.75,.74,.71,1}, platform_selection={.28,.24,.18,1},
}
