# conform: tags=diagnostics,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:29 TestDiscardedResultLint
type Outcome:
    value: Int

def caller() -> Unit:
    Outcome(1)
