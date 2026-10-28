# conform: tags=diagnostics,match,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:24 TestDiscardedResultLint
fn caller() Result[Int, Error]:
    return match operation():
        ok(value):
            operation()
            operation()
        error(cause): operation()
