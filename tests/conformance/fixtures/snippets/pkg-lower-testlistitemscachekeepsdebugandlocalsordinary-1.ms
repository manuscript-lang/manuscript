# conform: tags=control-flow,diagnostics,faults,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/lower/list_items_test.go:38 TestListItemsCacheKeepsDebugAndLocalsOrdinary
def work() -> Int:
    let values = [1, 2]
    var i = 0
    var total = 0

    while i < 2:
        total += values.get(i)
        i += 1

    return total
