# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/basics/expressions.md:140
def calculated(value: Int, active: Bool) -> Int:
    let product = 1 + 2 * 3  # 7
    let same = not value == product  # not (value == product)
    if active and same:
        return product

    return value
