// conform: tags=diagnostics
// conform: phase=check
interface Counter:
    fn bump(by: Int) Int
    fn lower(by: Int) Int
type Cell:
    total: Int
impl Counter for Cell:
    fn bump(by: Int) Int:
        self.total += by
        return self.total
    fn lower(by: Int) Int:
        self.total -= by
        return self.total
fn take(value: Cell) Int: return value.total
