// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/named-types.md:82
customer_id := CustomerId("42")
// Rejected: equal field shapes do not make nominal types interchangeable.
order_id: OrderId := customer_id
