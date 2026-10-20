import stdout from "@std/io.ms"

type Counter:
    count: Int
    tags: List[String]

fn bump(var cs: List[Counter]) Int:
    var c = cs[0]
    c.count = c.count + 1
    c.tags.append("x")
    return cs[0].count

fn grow(var rows: List[List[Int]]) Unit:
    var head = rows[0]
    head.append(5)
    rows.append([9])

export fn main() Int:
    var cs = [Counter(count: 1, tags: [])]
    let n = bump(var cs)
    var rows = [[1], [2]]
    grow(var rows)
    var m = Map[String, Counter]()
    m.add("a", Counter(count: 10, tags: []))
    if var e = m.get("a"):
        e.count = e.count + 5
        e.tags.append("t")
    var got = 0
    if let e = m.get("a"):
        got = e.count
    var xs = [[1, 2], [3]]
    if var last = xs.last():
        last.append(4)
    stdout().write("{n} {cs[0].count} {cs[0].tags} {rows} {got} {m.get("a")} {xs}\n")
    return 0
