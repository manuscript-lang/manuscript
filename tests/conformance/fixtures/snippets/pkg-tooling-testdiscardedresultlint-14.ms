# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:28 TestDiscardedResultLint
def operation() -> Int: 1

def caller() -> Unit:
    operation()
