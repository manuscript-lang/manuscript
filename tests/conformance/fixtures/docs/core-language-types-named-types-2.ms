// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/types/named-types.md:22
customer := Customer(name: "Ada", email: null)
name := customer.name
// expect-error: MS3070 4:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 5:18 a constant takes literals, operators, collections, and other constants; compute this value in a function
