# conform: tags=control-flow,formatter,interfaces,mutation,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/lower/int_bounds_test.go:129 BenchmarkClosedCellProofScaling
interface Counter:
    fn bump(by: Int) Int
type Cell:
    total: Int
impl Counter for Cell:
    fn bump(by: Int) Int:
        self.total += by
        return self.total
fn probe() Int:
    var sum = 0
