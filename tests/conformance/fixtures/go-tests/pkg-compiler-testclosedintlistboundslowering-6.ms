# conform: tags=aliasing,control-flow,faults,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:27 TestClosedIntListBoundsLowering
let values = [1]
    var fill = 0
    while fill < 100:
        values.append(values.get(-1) + 1)
        fill += 1
