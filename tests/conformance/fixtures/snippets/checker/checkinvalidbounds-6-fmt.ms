# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/bound_recovery_test.go:44 checkInvalidBounds
fn unknown[T: Missing](value: T) Unit: return
