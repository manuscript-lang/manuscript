# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/grammar.md:64
fn example() Int:
    return apply(value: 3, transform: (fn(value: Int) Int: return value - 1))
