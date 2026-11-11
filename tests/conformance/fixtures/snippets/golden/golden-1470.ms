// conform: tags=diagnostics
// conform: phase=check
fn deep(l: List[Int], i: Int) Int:
    return l.get(i)
export fn main() Int:
    return deep(l: [1], i: 5)
