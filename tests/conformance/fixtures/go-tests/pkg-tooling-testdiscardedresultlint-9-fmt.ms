# conform: tags=formatter,match,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:23 TestDiscardedResultLint
fn caller() Result[Int, Error]:
    return match operation():
        ok(value): operation()
        error(cause): operation()
