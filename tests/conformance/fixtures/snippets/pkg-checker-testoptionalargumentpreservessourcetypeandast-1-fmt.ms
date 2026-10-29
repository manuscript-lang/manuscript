# conform: tags=faults,formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/optional_test.go:12 TestOptionalArgumentPreservesSourceTypeAndAST
fn f(value: Optional[Int]) Int: return value.get()

fn call() Int: return f(4)
