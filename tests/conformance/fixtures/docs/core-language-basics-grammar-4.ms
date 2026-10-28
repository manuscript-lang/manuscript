# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/basics/grammar.md:88
fn example() Int:
    return apply(transform: fn(value: Int) Int: return value - 1, value: 3)
