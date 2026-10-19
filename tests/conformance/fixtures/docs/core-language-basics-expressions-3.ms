# conform: tags=numbers,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/expressions.md:149
fn invalid(value: Int, ratio: Float) Bool:
    let mixed = value + ratio           # Type error: exact numeric types differ.
    return 0 < value < 10               # Syntax error: comparison chain.
