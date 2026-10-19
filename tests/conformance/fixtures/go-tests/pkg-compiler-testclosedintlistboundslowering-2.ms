# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:21 TestClosedIntListBoundsLowering
let values = [1, 2, 3]
    let alias = values.append(4)
