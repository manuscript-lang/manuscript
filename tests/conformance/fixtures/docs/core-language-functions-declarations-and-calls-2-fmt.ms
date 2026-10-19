# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/functions/declarations-and-calls.md:31
fn reduce(amount: Int, deduction: Int) Int:
    return amount - deduction

let remaining = reduce(10, 3)
let explicit_remaining = reduce(amount: 10, deduction: 3)
let mixed = reduce(deduction: 3, 10)
let amount = 10
let deduction = 3
let swapped = reduce(deduction: deduction, amount: amount)
