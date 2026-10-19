# conform: tags=formatter,numbers,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:32 TestOptionalArgumentBoundaries
fn f(value: Optional[Float]) Unit: return
fn call(value: Optional[Int]) Unit: f(value)
