# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/checker_test.go:33 TestOmittedLabelPreservesSourceAST
def identity[T](value: T) -> T:
    return value

def call() -> Int:
    return identity(3)
