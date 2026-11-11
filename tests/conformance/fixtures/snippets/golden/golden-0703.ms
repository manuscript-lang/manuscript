// conform: tags=diagnostics
// conform: phase=check
interface Counter:
    fn bump(by: Int) Int
type Cell[T]:
    total: Int
impl Counter for Cell[T]:
    fn bump(by: Int) Int:
        self.total += by
        return self.total
fn probe() Int:
    cell := Cell[String](0)
    var i = 0
    while i < 1000:
        cell.bump(1)
        i += 1
    return cell.total
