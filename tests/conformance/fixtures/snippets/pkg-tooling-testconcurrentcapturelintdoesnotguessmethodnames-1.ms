# conform: tags=closures,control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/capture_lint_test.go:79 TestConcurrentCaptureLintDoesNotGuessMethodNames
interface Starter:
    fn start(operation: fn() Unit) Unit

type Sequential:

impl Starter for Sequential:
    fn start(operation: fn() Unit) Unit:
        operation()

fn run() Unit:
    var values = [0]
    Sequential().start(
        fn():
            values.append(1)
    )
