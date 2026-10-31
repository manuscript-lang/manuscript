# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/positional_arguments_test.go:27 TestPositionalIdentifierRenameDoesNotAddLabels
fn subtract(amount: Int, deduction: Int) Int: amount - deduction

fn run() Int:
    let number = 10
    return subtract(number, 3)
