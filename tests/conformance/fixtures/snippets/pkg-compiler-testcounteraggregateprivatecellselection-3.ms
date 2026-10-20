# conform: tags=control-flow,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/counter_aggregate_test.go:77 TestCounterAggregatePrivateCellSelection
var i = 0
    while i < 321:
        cell.bump(3)
        i += 1
    return cell.total
