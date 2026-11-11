// conform: tags=diagnostics
// conform: phase=check
interface Counter:
    fn bump(by: Int) Int
type Cell:
    total: Int
impl Counter for Cell:
    