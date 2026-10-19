# conform: tags=aliasing,control-flow,faults,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:28 TestClosedIntListBoundsLowering
let values = [1]
    let peer = [2]
    var fill = 0
    while fill < 100:
        values.append(peer.get(-1))
        peer.append(values.get(-1))
        fill += 1
