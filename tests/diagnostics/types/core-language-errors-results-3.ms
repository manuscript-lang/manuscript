// conform: tags=closures,diagnostics,faults,formatter,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/errors/results.md:64
price := discount(price: 20d, percent: 10d).get(0d)
text := discount(price: 20d, percent: 10d).map(value => value.to_string())
// expect-error: MS3070 4:45 a constant takes literals, operators, collections, and other constants; compute this value in a function
// expect-error: MS3070 5:44 a constant takes literals, operators, collections, and other constants; compute this value in a function
