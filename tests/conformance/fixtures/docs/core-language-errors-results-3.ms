// conform: tags=closures,diagnostics,faults,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/errors/results.md:64
price := discount(price: 20d, percent: 10d).get(0d)
text := discount(price: 20d, percent: 10d).map(fn value: value.to_string())
