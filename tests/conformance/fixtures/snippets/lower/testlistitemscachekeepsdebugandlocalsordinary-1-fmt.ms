# conform: tags=control-flow,faults,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/list_items_test.go:38 TestListItemsCacheKeepsDebugAndLocalsOrdinary
fn work() Int:
    let values = [1, 2]
    var i = 0
    var total = 0

    while i < 2:
        total += values.get(i)
        i += 1

    return total
