# conform: tags=closures,control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:19 TestDiscardedResultLint
fn caller() Unit:
    let callback = fn() Unit:
        if true:
            operation()
    callback()
