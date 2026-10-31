# conform: tags=formatter,numbers,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:32 TestOptionalArgumentBoundaries
fn f(value: Float?) Unit: return

fn call(value: Int?) Unit: f(value)
