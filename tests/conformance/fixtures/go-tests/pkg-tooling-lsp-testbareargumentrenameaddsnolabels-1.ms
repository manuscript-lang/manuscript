# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:383 TestBareArgumentRenameAddsNoLabels
fn subtract(amount: Int, deduction: Int) Int: return amount - deduction
fn call() Int:
    let amount = 10
    let deduction = 3
    return subtract(deduction, amount)
