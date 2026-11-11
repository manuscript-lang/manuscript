// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/compatibility.md:26
fn identity(value: Int) Int:
    return value

exact: fn(Int) Int := identity
// Rejected: amount differs from value.
relabeled: fn(Int) Int := identity
