# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:10
def decrement(value: Int) -> Int:
    return value - 1

let remaining = decrement(3)
