# conform: tags=closures,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/counter_aggregate_test.go:24 TestCounterAggregateSelection
var stride = 3
    let read = fn() Int: stride
    stride = 3
    sum = 0
    i = 0
    
