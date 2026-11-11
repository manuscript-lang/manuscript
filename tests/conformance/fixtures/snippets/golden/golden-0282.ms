// conform: tags=diagnostics
// conform: phase=check
enum Choice[T]:
    Found(value: T)
    Missing
fn f(c: Choice[Int], o: Int?) Int:
    match o:
        Optional.some(n): return n
        Optional.none: return 0
    match c:
        Choice.Found(v): return v
        Choice.Missing: return 0
