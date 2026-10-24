# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/compatibility.md:26
def identity(value: Int) -> Int:
    return value

let exact: Callable[[Int], Int] = identity
# Rejected: amount differs from value.
let relabeled: Callable[[Int], Int] = identity
