# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:38 TestOptionalArgumentBoundaries
fn f(value: Int?) Unit: return

fn call() Unit: f(other: 4)
