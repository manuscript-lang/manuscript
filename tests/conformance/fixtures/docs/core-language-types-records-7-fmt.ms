# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/records.md:82
let customer_id = CustomerId("42")
# Rejected: equal field shapes do not make nominal types interchangeable.
let order_id: OrderId = customer_id
