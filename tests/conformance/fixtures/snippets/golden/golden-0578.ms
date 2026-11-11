// conform: tags=diagnostics
// conform: phase=check
fn probe() Int:
    values := Map[Int, Int]()
    values.add(1, 2)
    return values.get(1).get()
