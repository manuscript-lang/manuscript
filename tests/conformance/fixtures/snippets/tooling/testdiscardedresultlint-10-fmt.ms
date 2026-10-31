# conform: tags=formatter,match,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:24 TestDiscardedResultLint
fn caller() Int!:
    return match operation():
        ok(value):
            operation()
            operation()
        error(cause): operation()
