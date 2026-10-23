# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:10
fn apply(value: Int, transform: fn(value: Int) Int) Int:
    return transform(value: value)

let offset = 1
let decrement = fn(value: Int) Int:
    return value - offset
let result = apply(value: 3, transform: decrement)
