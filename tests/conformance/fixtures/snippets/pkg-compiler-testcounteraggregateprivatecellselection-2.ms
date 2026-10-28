# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/counter_aggregate_test.go:77 TestCounterAggregatePrivateCellSelection
fn probe() Int:
    let cell = Cell(0)
