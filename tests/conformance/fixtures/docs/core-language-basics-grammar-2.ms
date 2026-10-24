# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/basics/grammar.md:64
def example() -> Int:
    return apply(value: 3, transform: (lambda (value: Int) -> Int: return value - 1))
