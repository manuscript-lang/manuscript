# conform: tags=formatter,generics,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/bound_recovery_test.go:43 checkInvalidBounds
type Data:
    value: Int
fn record[T: Data](value: T) Unit: return
