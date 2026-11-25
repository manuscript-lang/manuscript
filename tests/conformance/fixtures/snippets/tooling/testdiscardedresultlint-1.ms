// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/tooling/result_lint_test.go:11 TestDiscardedResultLint
fn operation() Int! => ok(1)
// expect-exit: 0
