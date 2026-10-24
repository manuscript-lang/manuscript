# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/bound_recovery_test.go:42 checkInvalidBounds
def primitive[T: Int](value: T) -> Unit: return
