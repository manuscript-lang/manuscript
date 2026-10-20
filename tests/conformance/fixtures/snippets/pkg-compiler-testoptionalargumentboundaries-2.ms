# conform: tags=diagnostics,numbers,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:25 TestOptionalArgumentBoundaries
fn f(value: Optional[Float]) Unit: return
fn call() Unit: f(4)
