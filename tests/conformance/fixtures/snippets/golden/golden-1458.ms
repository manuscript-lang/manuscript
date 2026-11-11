// conform: tags=diagnostics
// conform: phase=check
interface Counter:
    fn bump(by: Int) Int
type Cell:
    total: Int
impl Counter for Cell:
    fn bump(by: Int) Int:
        self.total += by
        return self.total
fn probe(value: Int) Int:
    cell := Cell(0)
    cell.bump(value)
    cell.bump(1)
    return cell.total
export fn main() Int:
    return probe(9223372036854775807)
