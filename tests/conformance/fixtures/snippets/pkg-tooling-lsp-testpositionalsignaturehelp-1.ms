# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/positional_arguments_test.go:19 TestPositionalSignatureHelp
fn subtract(amount: Int, deduction: Int) Int: amount - deduction

fn run() Int:
    return
