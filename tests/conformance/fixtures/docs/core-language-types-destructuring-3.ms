# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/destructuring.md:29
let {customer: {name}, shipping: {city: destination}} = order
let [{name: first_name}, {name: second_name}] = customers
