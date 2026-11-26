// conform: tags=diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=scripts/repo-check/nested_match_test.go:18 TestNestedMatchSourceGate
fn use(value Int?) Void { ... }
// expect-exit: 0
