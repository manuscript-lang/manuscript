# conform: tags=formatter,mutation,numbers,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/bindings.md:64
fn example() Unit:
    var remaining = 3
    remaining = 2
    remaining = 2.0  # Rejected: Float cannot replace Int.
