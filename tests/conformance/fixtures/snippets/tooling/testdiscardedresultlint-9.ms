# conform: tags=diagnostics,match,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:23 TestDiscardedResultLint
fn caller() Int!:
    return match operation():
        ok(value): operation()
        error(cause): operation()
