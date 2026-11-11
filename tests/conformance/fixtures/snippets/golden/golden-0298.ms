// conform: tags=diagnostics
// conform: phase=check
type S:
    x: Int
impl Missing for S:
    fn m() Int: return 1
