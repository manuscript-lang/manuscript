# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/learn/tour.md:122
let prices = [12, 8, 25]
let discounted = prices.map(fn(value: Int) Int: return value - 2)
let affordable = discounted.filter(fn(value: Int) Bool: return value <= 10)
# affordable contains [10, 6]; prices is unchanged.
