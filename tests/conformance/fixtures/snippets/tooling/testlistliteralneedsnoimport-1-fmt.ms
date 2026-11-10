// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lint_program_test.go:117 TestListLiteralNeedsNoImport
fn answer() Int:
    items := [1, 2, 3]
    return items.length()
