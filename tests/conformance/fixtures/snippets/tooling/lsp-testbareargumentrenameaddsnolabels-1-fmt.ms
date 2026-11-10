// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/features_test.go:383 TestBareArgumentRenameAddsNoLabels
fn subtract(amount: Int, deduction: Int) Int: return amount - deduction

fn call() Int:
    amount := 10
    deduction := 3
    return subtract(deduction, amount)
