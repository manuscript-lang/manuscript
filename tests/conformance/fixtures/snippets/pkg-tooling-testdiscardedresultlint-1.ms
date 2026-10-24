# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:11 TestDiscardedResultLint
def operation() -> Result[Int, Error]: ok(1)
