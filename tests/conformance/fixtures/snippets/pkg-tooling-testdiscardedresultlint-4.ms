# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:18 TestDiscardedResultLint
def operation() -> Result[Unit, Error]: ok(())

def caller() -> Unit:
    let _ = operation()
