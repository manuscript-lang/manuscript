# conform: tags=control-flow,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/counter_aggregate_test.go:166 TestCounterAggregateQueryFaultFrame
def probe() -> Int:
    var sum = 0
    var i = 0

    while i < 321:
        sum += i
        i += 1

    return sum
