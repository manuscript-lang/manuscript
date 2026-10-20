# conform: tags=formatter,lists,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:36 TestOptionalArgumentBoundaries
fn f(values: List[Optional[Int]]) Unit: return
fn call() Unit: f([4])
