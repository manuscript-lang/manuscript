# conform: tags=control-flow,lists,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:29 TestClosedIntListBoundsLowering
let values: List[Int] = []
    var fill = 0
    while fill < 100:
        values.append(fill)
        fill += 1
