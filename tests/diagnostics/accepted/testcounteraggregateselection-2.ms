// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/counter_aggregate_test.go:19 TestCounterAggregateSelection
fn identity[T](hold n T) &T => return n
// expect-exit: 0
