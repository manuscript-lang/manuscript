// conform: tags=diagnostics
// conform: phase=check
fn probe() String:
    var b = List[String]()
    var i = 0
    while i < 321:
        b.append("x")
        i += 1
    return b.freeze()
