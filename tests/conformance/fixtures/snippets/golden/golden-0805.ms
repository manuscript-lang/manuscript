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
fn probe() Int:
    var sum = 0
