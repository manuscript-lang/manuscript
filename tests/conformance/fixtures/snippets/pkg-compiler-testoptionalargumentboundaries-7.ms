# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:30 TestOptionalArgumentBoundaries
fn f(value: Optional[Optional[Int]]) Unit: return

fn call() Unit: f(4)
