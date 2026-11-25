// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/counter_aggregate_test.go:18 TestCounterAggregateSelection
fn identity(n Int) Int => return n
// expect-exit: 0
