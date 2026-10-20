# conform: tags=diagnostics,generics,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/bound_recovery_test.go:43 checkInvalidBounds
type Data:
    value: Int
fn record[T: Data](value: T) Unit: return
