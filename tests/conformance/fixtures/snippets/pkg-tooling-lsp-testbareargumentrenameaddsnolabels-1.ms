# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/features_test.go:383 TestBareArgumentRenameAddsNoLabels
def subtract(amount: Int, deduction: Int) -> Int: return amount - deduction

def call() -> Int:
    let amount = 10
    let deduction = 3
    return subtract(deduction, amount)
