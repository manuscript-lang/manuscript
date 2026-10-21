# conform: tags=control-flow,interfaces,records,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:47 TestFaultSourceLocations
interface Counter:
    var fn bump(by: Int) Int
type Cell:
    total: Int
impl Counter for Cell:
    var fn bump(by: Int) Int:
        self.total += by
        return self.total
fn probe(value: Int) Int:
    var cell = Cell(0)
    cell.bump(value)
    cell.bump(1)
    return cell.total
export fn main() Int:
    return probe(9223372036854775807)
