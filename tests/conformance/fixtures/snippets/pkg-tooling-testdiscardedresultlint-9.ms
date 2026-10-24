# conform: tags=diagnostics,match,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:23 TestDiscardedResultLint
def caller() -> Result[Int, Error]:
    return match operation():
        case ok(value): operation()
        case error(cause): operation()
