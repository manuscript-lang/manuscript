# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:122
let prices = [12, 8, 25]
let discounted = prices.map(lambda (value: Int) -> Int: return value - 2)
let affordable = discounted.filter(lambda (value: Int) -> Bool: return value <= 10)
# affordable contains [10, 6]; prices is unchanged.
