# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/record_bounds_test.go:40 TestClosedRecordIntBounds
let cell = Cell(0)
    let read = fn() Int: cell.total
