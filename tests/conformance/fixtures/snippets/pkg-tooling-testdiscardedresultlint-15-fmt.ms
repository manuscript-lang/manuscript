# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:29 TestDiscardedResultLint
type Outcome:
    value: Int

fn caller() Unit:
    Outcome(1)
