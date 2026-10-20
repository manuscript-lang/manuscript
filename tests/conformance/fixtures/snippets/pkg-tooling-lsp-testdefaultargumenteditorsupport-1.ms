# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/defaults_test.go:45 TestDefaultArgumentEditorSupport
fn subtract(amount: Int, deduction: Int = 1) Int:
    return amount - deduction
fn call() Int:
    return sub|
