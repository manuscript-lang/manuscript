# conform: tags=diagnostics,faults,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/optional_test.go:12 TestOptionalArgumentPreservesSourceTypeAndAST
def f(value: Optional[Int]) -> Int: return value.get()

def call() -> Int: return f(4)
