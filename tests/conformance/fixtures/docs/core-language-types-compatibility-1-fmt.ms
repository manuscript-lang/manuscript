# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/compatibility.md:26
fn identity(value: Int) Int:
    return value

let exact: fn(value: Int) Int = identity
# Rejected: amount differs from value.
let relabeled: fn(amount: Int) Int = identity
