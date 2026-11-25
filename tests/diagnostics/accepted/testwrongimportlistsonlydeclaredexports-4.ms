// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:111 TestWrongImportListsOnlyDeclaredExports
export fn parse_cents() Int => 0
// expect-exit: 0
