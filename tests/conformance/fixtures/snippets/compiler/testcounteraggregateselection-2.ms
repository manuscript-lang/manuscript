# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/counter_aggregate_test.go:19 TestCounterAggregateSelection
fn identity[T](n: T) T: return n
