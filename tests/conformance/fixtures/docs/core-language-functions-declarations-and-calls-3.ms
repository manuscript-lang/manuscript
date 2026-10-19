# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:61
fn subtract(amount: Int, deduction: Int = 1) Int:
    return amount - deduction

fn example() Int:
    let usual = subtract(5)
    let explicit = subtract(5, 2)
    return usual + explicit
