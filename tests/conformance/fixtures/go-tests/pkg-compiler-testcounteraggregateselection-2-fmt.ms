# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/counter_aggregate_test.go:19 TestCounterAggregateSelection
fn identity[T](n: T) T: return n
