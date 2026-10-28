# conform: tags=diagnostics,match,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:20 TestDiscardedResultLint
fn caller() Unit:
    match operation():
        ok(value): operation()
        error(cause): operation()
