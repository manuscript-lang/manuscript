# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/bound_recovery_test.go:42 checkInvalidBounds
fn primitive[T: Int](value: T) Unit: return
