# conform: tags=faults,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/optional_test.go:12 TestOptionalArgumentPreservesSourceTypeAndAST
def f(value: Optional[Int]) -> Int: return value.get()

def call() -> Int: return f(4)
