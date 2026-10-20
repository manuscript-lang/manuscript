# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/record_bounds_test.go:66 TestClosedRecordRejectsDifferentMethodShapes
fn bump(by: Int) Int:
        self.total += by
        return by
