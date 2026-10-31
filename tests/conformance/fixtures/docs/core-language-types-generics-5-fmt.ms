# conform: tags=control-flow,formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/generics.md:92
fn choose[T](first: T, second: T) T:
    return first

let value = choose(1, 2)  # T = Int
# Rejected: conflicting evidence for T.
let mixed = choose(1, 2.0)
