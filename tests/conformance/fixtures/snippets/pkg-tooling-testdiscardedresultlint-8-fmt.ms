# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:22 TestDiscardedResultLint
fn consume(value: Result[Int, Error]) Unit: unit

fn caller() Unit:
    consume(operation())
