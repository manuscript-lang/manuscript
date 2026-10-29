# conform: tags=formatter,numbers,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:25 TestOptionalArgumentBoundaries
fn f(value: Optional[Float]) Unit: return

fn call() Unit: f(4)
