# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/grammar.md:88
fn example() Int:
    return apply(
        transform: fn(value: Int) Int:
            return value - 1
        ,
        value: 3,
    )
