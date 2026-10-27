export def main() -> Int:
    var m = Map[String, Int]()
    m.add("a", 1)
    if var n = m.get("a"):
        n += 1
    return m.get("a").get(0)
