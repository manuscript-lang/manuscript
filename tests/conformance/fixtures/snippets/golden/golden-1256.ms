// conform: tags=diagnostics
// conform: phase=check
fn subtract(amount: Int, deduction: Int) Int: return amount - deduction
fn call() Int:
    amount := 10
    deduction := 3
    return subtract(deduction, amount)
