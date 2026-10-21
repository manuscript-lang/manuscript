# conform: tags=control-flow,diagnostics,generics,interfaces,mutation,records,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/record_bounds_test.go:80 TestClosedRecordGenericReceiverFallback
interface Counter:
    fn bump(by: Int) Int
type Cell[T]:
    total: Int
impl Counter for Cell[T]:
    var fn bump(by: Int) Int:
        self.total += by
        return self.total
fn probe() Int:
    var cell = Cell[String](0)
    var i = 0
    while i < 1000:
        cell.bump(1)
        i += 1
    return cell.total
