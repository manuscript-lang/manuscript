# conform: tags=formatter,match,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:20 TestDiscardedResultLint
def caller() -> Unit:
    match operation():
        case ok(value): operation()
        case error(cause): operation()
