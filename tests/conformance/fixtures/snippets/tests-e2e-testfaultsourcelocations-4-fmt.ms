# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:47 TestFaultSourceLocations
interface Counter:
    var def bump(by: Int) -> Int

type Cell:
    total: Int

impl Counter for Cell:
    var def bump(by: Int) -> Int:
        self.total += by
        return self.total

def probe(value: Int) -> Int:
    var cell = Cell(0)
    cell.bump(value)
    cell.bump(1)
    return cell.total

export def main() -> Int:
    return probe(9223372036854775807)
