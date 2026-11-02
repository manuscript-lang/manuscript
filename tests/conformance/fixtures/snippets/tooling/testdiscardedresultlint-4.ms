# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:18 TestDiscardedResultLint
fn operation() Unit!: ok(unit)

fn caller() Unit:
    let _ = operation()
