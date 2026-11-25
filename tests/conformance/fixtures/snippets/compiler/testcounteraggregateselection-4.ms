// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/counter_aggregate_test.go:21 TestCounterAggregateSelection
fn identity(n Int) Int => return n + 1
// expect-exit: 0
