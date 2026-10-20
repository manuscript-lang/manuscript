# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/analysis_test.go:137 TestMultilineParameterNavigationDuringRecovery
fn first() Int:
    return 1
export fn answer(
    input: Int,
) Int:
    return input
fn broken(
