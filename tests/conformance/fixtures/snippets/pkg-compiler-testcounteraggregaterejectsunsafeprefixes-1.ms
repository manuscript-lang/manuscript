# conform: tags=control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/counter_aggregate_test.go:44 TestCounterAggregateRejectsUnsafePrefixes
def probe() -> Int:
    var sum = 9223372036854775807
    var i = 0

    while i < 321:
        sum += i
        i += 1

    return sum
