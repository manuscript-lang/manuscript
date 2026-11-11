// conform: tags=diagnostics
// conform: phase=check
fn f(counts: Map[String, Int], names: List[String], found: Int?) Unit:
    match found:
        n:
            counts.add(key: "a", value: n)
        none:
            names.append("x")
