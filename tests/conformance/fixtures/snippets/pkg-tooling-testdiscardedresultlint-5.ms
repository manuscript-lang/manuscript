# conform: tags=closures,control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:19 TestDiscardedResultLint
def caller() -> Unit:
    let callback = lambda () -> Unit:
        if True:
            operation()
    callback()
