# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/record_bounds_test.go:68 TestClosedRecordRejectsDifferentMethodShapes
interface Counter:
    def bump(by: Int) -> Int

type Cell:
    total: Int

impl Counter for Cell:
