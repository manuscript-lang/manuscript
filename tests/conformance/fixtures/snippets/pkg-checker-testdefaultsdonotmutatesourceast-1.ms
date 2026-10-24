# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:49 TestDefaultsDoNotMutateSourceAST
def f(value: Int = 3) -> Int:
    return value

def call() -> Int:
    return f()
