# conform: tags=diagnostics,numbers,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:32 TestOptionalArgumentBoundaries
fn f(value: Optional[Float]) Unit: return

fn call(value: Optional[Int]) Unit: f(value)
