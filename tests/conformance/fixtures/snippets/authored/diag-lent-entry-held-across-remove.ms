# conform: tags=diagnostics,ownership,maps,tier-core
# conform: phase=check
# conform: origin=issue 2181
fn held() Int:
    var m = Map[String, List[Int]]()
    m.add("a", [1, 2, 3])
    let x = m.get("a")
    m.remove("a")
    return x.get([]).length()
