# conform: tags=control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/record_bounds_test.go:68 TestClosedRecordRejectsDifferentMethodShapes
def probe() -> Int:
    let cell = Cell(0)
    var i = 0

    while i < 1000:
        cell.bump(1)
        i += 1

    return cell.total
