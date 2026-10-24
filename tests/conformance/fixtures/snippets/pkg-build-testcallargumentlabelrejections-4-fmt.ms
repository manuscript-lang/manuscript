# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:80 TestCallArgumentLabelRejections
def call(operation: Callable[[], Int]) -> Int:
    return operation()
