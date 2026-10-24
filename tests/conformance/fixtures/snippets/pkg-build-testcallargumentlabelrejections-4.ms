# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:80 TestCallArgumentLabelRejections
def call(operation: Callable[[], Int]) -> Int:
    return operation()
