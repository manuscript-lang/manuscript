fn bump(var m: Map[String, List[Int]]) Unit:
    if var q = m.get("a"):
        q.append(1)
