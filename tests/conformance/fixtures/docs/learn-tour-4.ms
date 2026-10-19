# conform: tags=control-flow,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/learn/tour.md:73

let prices = [12, 8, 25]
var total = 0
for price in prices:
    total += price

var shipping = 5
if total >= 40:
    shipping = 0
let checkout_total = total + shipping
