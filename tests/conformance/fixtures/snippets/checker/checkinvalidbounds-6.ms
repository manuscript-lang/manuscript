# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/bound_recovery_test.go:44 checkInvalidBounds
fn unknown[T: Missing](value: T) Unit: return
