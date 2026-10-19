# conform: tags=decimal,diagnostics,numbers,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/basics/numbers-and-booleans.md:36
fn literals() Unit:
    let smallest: Int = -9223372036854775808
    let exponent: Float = 1e3
    let precise: Decimal = 1e3d
    # Rejected: an Int token does not become Float from context.
    let mismatch: Float = 1
