# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/counter_aggregate_test.go:22 TestCounterAggregateSelection
let read = fn() Int: sum
    sum = 0
    i = 0
    
