# conform: tags=control-flow,destructuring,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/basics/grammar.md:219
let count = 3                       # Not a complete module item.
fn wrong() Int:
  return 1                          # A suite requires four spaces.
fn wrong() Int:
    let (first, second) = pair       # Parentheses are not a binding pattern.
    return if true: 1 else: 2        # if is not an expression.
