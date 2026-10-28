# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:18 TestDiscardedResultLint
fn operation() Result[Unit, Error]: ok(unit)

fn caller() Unit:
    let _ = operation()
