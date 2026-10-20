# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/counter_aggregate_test.go:23 TestCounterAggregateSelection
let read = fn() Int: i
    i = 0
    sum = 0
    
