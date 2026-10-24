# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:22 TestDiscardedResultLint
def consume(value: Result[Int, Error]) -> Unit: ()

def caller() -> Unit:
    consume(operation())
