# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:10
def apply(value: Int, transform: Callable[[Int], Int]) -> Int:
    return transform(value: value)

let offset = 1
let decrement = lambda (value: Int) -> Int:
    return value - offset
let result = apply(value: 3, transform: decrement)
