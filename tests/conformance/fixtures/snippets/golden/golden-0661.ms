// conform: tags=diagnostics
// conform: phase=check
type Map[K,V]:
    value: V
fn f(m: Map[String,Int]) Unit:
    m.add("a", 1)
