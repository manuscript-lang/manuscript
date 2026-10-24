# conform: tags=closures,formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/checker_test.go:55 TestContextualCallbackPreservesSourceAST
type Callback:
    value: Callable[[Int], Int]

def example() -> Unit:
    let callback = Callback(lambda value: value + 1)
