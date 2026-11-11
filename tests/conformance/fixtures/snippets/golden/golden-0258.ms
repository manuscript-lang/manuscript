// conform: tags=diagnostics
// conform: phase=check
interface I:
    fn m() Int
interface J:
    fn m() Int
type A:
    n: Int
impl I for A:
    fn m() Int: return 1
impl J for A:
    fn m() Int: return 2
fn f(a: A) Int:
    return a.m()
