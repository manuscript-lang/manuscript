# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/positional_arguments_test.go:68 TestPositionalArgumentDiagnostics
def f(n: Int) -> Int: n

def apply(callback: Callable[[Int], Int], input: Int) -> Int: callback(input)
