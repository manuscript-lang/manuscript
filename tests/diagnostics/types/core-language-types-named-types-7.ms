// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/named-types.md:82
customer_id := CustomerId("42")
// Rejected: equal field shapes do not make nominal types interchangeable.
order_id OrderId := customer_id
// expect-error: MS3070 4:16 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS2001 6:10 unknown type OrderId; declare it with 'type OrderId:' / 'enum OrderId:' / 'interface OrderId:', declare it as a type parameter, or import it
