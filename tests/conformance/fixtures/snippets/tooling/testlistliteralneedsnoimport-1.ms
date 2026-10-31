# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:117 TestListLiteralNeedsNoImport
fn answer() Int:
    let items = [1, 2, 3]
    return items.length()
