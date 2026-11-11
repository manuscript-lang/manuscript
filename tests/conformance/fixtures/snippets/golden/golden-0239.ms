// conform: tags=diagnostics
// conform: phase=check
fn f(xs: List[Int], o: Int?) Unit:
    var n = 0
    match o:
        v:
            n = v
            xs.set(index: 0, value: 5)
        none:
            n = 2
    xs.append(n)
