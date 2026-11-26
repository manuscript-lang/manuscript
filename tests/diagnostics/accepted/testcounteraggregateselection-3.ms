// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/counter_aggregate_test.go:20 TestCounterAggregateSelection
fn identity(n Int = 0) Int => return n
// expect-exit: 0
