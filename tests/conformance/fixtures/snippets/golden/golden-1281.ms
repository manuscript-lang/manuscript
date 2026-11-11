// conform: tags=diagnostics
// conform: phase=check
fn subtract(amount: Int, deduction: Int) Int: amount - deduction
fn run() Int:
    number := 10
    return subtract(number, 3)
