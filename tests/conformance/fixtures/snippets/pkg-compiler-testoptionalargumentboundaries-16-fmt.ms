# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:39 TestOptionalArgumentBoundaries
fn f(value: Optional[Int]) Unit: return

fn call() Unit: f(4, value: 5)
