// conform: tags=control-flow,diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/basics/expressions.md:140
fn calculated(value: Int, active: Bool) Int:
    product := 1 + 2 * 3  // 7
    same := not value == product  // not (value == product)
    if active and same:
        return product

    return value
