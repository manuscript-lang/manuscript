# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:18 TestDiscardedResultLint
def operation() -> Result[Unit, Error]: ok(())

def caller() -> Unit:
    operation()
