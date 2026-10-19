# conform: tags=mutation,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/bindings.md:37
let customer = Customer(name: "Ada", active: true)
let greeting = welcome(customer)
let count: Int = 3
var remaining = count
remaining -= 1
