local Graph = require('scripts.graph')
script = {active_mods = {base = '2.1.24'}}
storage = {}
prototypes = {technology = {}, get_entity_filtered = function() return {} end,
  recipe = {test = {categories = {'crafting'}, energy = 1, enabled = true,
    ingredients = {}, products = {
      {type='item', name='independent', amount=4, independent_probability=.25,
       ignored_by_productivity=2, ignored_by_stats=1},
      {type='item', name='shared', amount=4, independent_probability=.5,
       shared_probability={min=.2,max=.6}},
      {type='fluid', name='zero', amount=10, independent_probability=0},
      {type='item', name='legacy', amount=2, probability=.1},
    }}}}
local products = Graph.build().recipes.test.products
assert(products[1].amount == 1 and products[1].prod == .5 and products[1].ignored_by_stats == .25)
assert(math.abs(products[2].amount - .8) < 1e-12)
assert(products[3].amount == 0 and products[4].amount == .2)
print('PRODUCT PROBABILITY PASS: independent, shared, zero and legacy probabilities')
