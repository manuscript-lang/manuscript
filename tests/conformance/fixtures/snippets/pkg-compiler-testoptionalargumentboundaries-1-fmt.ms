# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:24 TestOptionalArgumentBoundaries
fn f(value: Optional[Int]) Unit: return
fn call() Unit: f("wrong")
