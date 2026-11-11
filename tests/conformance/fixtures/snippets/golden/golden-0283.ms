// conform: tags=diagnostics
// conform: phase=check
enum Choice[T]:
    Found(value: T)
    Missing
fn f(c: Choice[Int]) Int:
    match c:
        Choice[String].Found(v): return 1
        Choice[String].Missing: return 0
