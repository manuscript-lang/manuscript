# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/compatibility.md:26
fn identity(value: Int) Int:
    return value

let exact: fn(Int) Int = identity
# Rejected: amount differs from value.
let relabeled: fn(Int) Int = identity
