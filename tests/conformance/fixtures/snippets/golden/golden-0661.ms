// conform: tags=diagnostics
// conform: phase=check
type Map[K,V]:
    value V
fn f(m Map[String,Int]) Void:
    m.add("a", 1)
