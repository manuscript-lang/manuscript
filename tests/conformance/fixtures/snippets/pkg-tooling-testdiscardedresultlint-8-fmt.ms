# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:22 TestDiscardedResultLint
def consume(value: Result[Int, Error]) -> Unit: ()

def caller() -> Unit:
    consume(operation())
