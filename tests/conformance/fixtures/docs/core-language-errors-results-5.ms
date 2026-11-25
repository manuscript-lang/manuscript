// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/errors/results.md:87
_ignored := discount(price: 20d, percent: 10d)
// expect-error: MS3070 4:13 a constant takes literals, operators, collections, and other constants; compute this value in a function
