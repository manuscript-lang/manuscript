// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/functions/declarations-and-calls.md:31
fn reduce(amount: Int, deduction: Int) Int:
    return amount - deduction

remaining := reduce(10, 3)
explicit_remaining := reduce(amount: 10, deduction: 3)
mixed := reduce(deduction: 3, 10)
amount := 10
deduction := 3
swapped := reduce(deduction: deduction, amount: amount)
