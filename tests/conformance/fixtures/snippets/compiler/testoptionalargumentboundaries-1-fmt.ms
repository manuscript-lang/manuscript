# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:24 TestOptionalArgumentBoundaries
fn f(value: Int?) Unit: return

fn call() Unit: f("wrong")
