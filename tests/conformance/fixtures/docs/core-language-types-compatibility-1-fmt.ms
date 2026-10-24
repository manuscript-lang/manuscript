# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/compatibility.md:26
def identity(value: Int) -> Int:
    return value

let exact: Callable[[Int], Int] = identity
# Rejected: amount differs from value.
let relabeled: Callable[[Int], Int] = identity
