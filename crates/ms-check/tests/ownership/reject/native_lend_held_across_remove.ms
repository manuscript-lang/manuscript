fn held(var m: Map[String, List[Int]]) Int:
    let x = m.get("a")
    m.remove("a")  # error: cannot change `m` while `x` borrows it
    return x.get([]).length()
