# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:28 TestDiscardedResultLint
fn operation() Int: 1

fn caller() Unit:
    operation()
