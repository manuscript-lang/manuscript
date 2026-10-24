# conform: tags=closures,control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:19 TestDiscardedResultLint
def caller() -> Unit:
    let callback = lambda () -> Unit:
        if True:
            operation()
    callback()
