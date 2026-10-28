# conform: tags=diagnostics,faults,generics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:35 TestOptionalArgumentBoundaries
fn f[T](value: Optional[T]) T: return value.get()

fn call() Unit: let value = f(none)
