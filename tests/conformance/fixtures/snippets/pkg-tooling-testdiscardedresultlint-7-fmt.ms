# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:21 TestDiscardedResultLint
fn caller() Result[Int, Error]:
    let value = operation()
    return value
