# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:25 TestDiscardedResultLint
fn caller() Unit:
    let _ignored = operation()
