# conform: tags=closures,control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/capture_lint_test.go:79 TestConcurrentCaptureLintDoesNotGuessMethodNames
interface Starter:
    def start(operation: Callable[[], Unit]) -> Unit

type Sequential: ...

impl Starter for Sequential:
    def start(operation: Callable[[], Unit]) -> Unit:
        operation()

def run() -> Unit:
    var values = [0]
    Sequential().start(
        lambda:
            values.append(1)
    )
