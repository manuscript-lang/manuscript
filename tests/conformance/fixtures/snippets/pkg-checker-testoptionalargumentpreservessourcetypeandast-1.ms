# conform: tags=diagnostics,faults,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/optional_test.go:12 TestOptionalArgumentPreservesSourceTypeAndAST
fn f(value: Optional[Int]) Int: return value.get()

fn call() Int: return f(4)
