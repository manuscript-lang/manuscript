// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:109 TestWrongImportListsOnlyDeclaredExports
fn hidden() Int => 0
// expect-exit: 0
