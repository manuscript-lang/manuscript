# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/builder_range_test.go:56 TestClosedRangeGrouping
let read = fn() Int: sum
    sum = 0
    
