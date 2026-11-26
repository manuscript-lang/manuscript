// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/basics/syntax.md:32
customer := Customer(name: "Ada", active: true)
// expect-error: MS3070 4:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
