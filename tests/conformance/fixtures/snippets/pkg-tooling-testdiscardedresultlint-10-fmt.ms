# conform: tags=formatter,match,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:24 TestDiscardedResultLint
def caller() -> Result[Int, Error]:
    return match operation():
        case ok(value):
            operation()
            operation()
        case error(cause): operation()
