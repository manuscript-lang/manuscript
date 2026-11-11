// conform: tags=diagnostics
// conform: phase=check
interface I:
    fn m() Int
impl I for Missing:
    fn m() Int: return 1
