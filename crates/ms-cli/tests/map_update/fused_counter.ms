export def main() -> Int:
    var m = Map[String, Int]()
    var r = Map[String, Int]()
    var n = Map[Int, Int]()
    var q = Map[Int, Int]()
    let ks = ["a", "bb", "a", "ccc", "a", "bb"]

    for k in ks:
        let kk = k + ""
        m.add(k.clone(), m.get(k).get(0) + 2)
        m.add(k.clone(), 3 + m.get(k).get(5))
        m.add(k.clone(), m.get(k).get(1) - 4)
        r.add(k.clone(), r.get(kk).get(0) + 2)
        r.add(k.clone(), 3 + r.get(kk).get(5))
        r.add(k.clone(), r.get(kk).get(1) - 4)

    for i in [1, 2, 1, 1, 3]:
        let j = i + 0
        n.add(i, n.get(i).get(1) * 3)
        n.add(i, n.get(i).get(0) - 1)
        q.add(i, q.get(j).get(1) * 3)
        q.add(i, q.get(j).get(0) - 1)

    for k in ks:
        if m.get(k).get(-99) != r.get(k).get(-99):
            return 1
    for i in [1, 2, 3, 4]:
        if n.get(i).get(-99) != q.get(i).get(-99):
            return 2
    if m.get("a").get(0) == 0:
        return 3

    return 0
