# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/bound_recovery_test.go:41 checkInvalidBounds
fn mutual[T: U, U: T](value: T) Unit: return
