# conform: tags=diagnostics,numbers,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:32 TestOptionalArgumentBoundaries
fn f(value: Float?) Unit: return

fn call(value: Int?) Unit: f(value)
