# conform: tags=closures,control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/capture_lint_test.go:79 TestConcurrentCaptureLintDoesNotGuessMethodNames
interface Starter:
    fn start(operation: fn() Unit) Unit
type Sequential:
impl Starter for Sequential:
    fn start(operation: fn() Unit) Unit:
        operation()
fn run() Unit:
    let values = [0]
    Sequential().start(fn():
        values.append(1)
    )
