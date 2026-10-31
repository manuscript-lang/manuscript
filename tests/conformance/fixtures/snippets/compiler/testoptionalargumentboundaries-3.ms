# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:26 TestOptionalArgumentBoundaries
fn f(value: Int?) Unit: return

fn call() Unit: f()
