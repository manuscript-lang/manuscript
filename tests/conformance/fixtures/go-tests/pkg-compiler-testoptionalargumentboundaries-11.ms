# conform: tags=diagnostics,generics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:34 TestOptionalArgumentBoundaries
fn f[T](value: Optional[T] = none) Unit: return
fn call() Unit: f()
