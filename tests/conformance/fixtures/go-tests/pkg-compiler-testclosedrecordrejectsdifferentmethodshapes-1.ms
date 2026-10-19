# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/record_bounds_test.go:64 TestClosedRecordRejectsDifferentMethodShapes
fn bump(by: Int = 1) Int:
        self.total += by
        return self.total
