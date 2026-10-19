# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/list_bounds_test.go:23 TestClosedIntListBoundsLowering
let values = [1, 2, 3]
    let read = fn() Int: values.length()
