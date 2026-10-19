# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/record_bounds_test.go:65 TestClosedRecordRejectsDifferentMethodShapes
fn bump(by: Int) Int:
        self.total += by + 1
        return self.total
