# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/bound_recovery_test.go:40 checkInvalidBounds
def recursive[T: T](value: T) -> Unit: return
