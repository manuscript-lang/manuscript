# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/checker_test.go:33 TestOmittedLabelPreservesSourceAST
fn identity[T](value: T) T:
    return value

fn call() Int:
    return identity(3)
