// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/functions/declarations-and-calls.md:61
fn subtract(amount: Int, deduction: Int = 1) Int:
    return amount - deduction

fn example() Int:
    usual := subtract(5)
    explicit := subtract(5, 2)
    return usual + explicit
