# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/grammar.md:77
def example() -> Int:
    return apply(value: 3, transform: lambda (value: Int) -> Int: return value - 1)
