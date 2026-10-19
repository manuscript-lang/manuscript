# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/counter_aggregate_test.go:25 TestCounterAggregateSelection
let read = fn(value: Int = sum) Int: value
    sum = 0
    i = 0
    
