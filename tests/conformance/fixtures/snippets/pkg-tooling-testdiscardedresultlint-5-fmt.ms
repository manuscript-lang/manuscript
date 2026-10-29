# conform: tags=closures,control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:19 TestDiscardedResultLint
fn caller() Unit:
    let callback = fn() Unit:
        if true:
            operation()
    callback()
