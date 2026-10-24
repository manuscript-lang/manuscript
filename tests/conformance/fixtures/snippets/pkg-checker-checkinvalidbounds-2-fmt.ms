# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/bound_recovery_test.go:40 checkInvalidBounds
def recursive[T: T](value: T) -> Unit: return
