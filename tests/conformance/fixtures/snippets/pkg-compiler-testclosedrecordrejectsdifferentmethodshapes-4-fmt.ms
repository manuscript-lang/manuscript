# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/record_bounds_test.go:68 TestClosedRecordRejectsDifferentMethodShapes
interface Counter:
    def bump(by: Int) -> Int

type Cell:
    total: Int

impl Counter for Cell:
