import stdout from "@std/io.ms"

type Box:
    n: Int
    xs: List[Int]

fn bump(var b: Box) Unit:
    var n = b.n
    n += 1
    n = n * 2

export fn main() Int:
    var b = Box(n: 1, xs: [1])
    bump(var b)
    var m = Map[String, Int]()
    m.add("a", 1)
    if var x = m.get("a"):
        x += 1
    var cs = [1, 2, 3]
    var first = cs[0]
    first += 10
    let before = b.n
    var scratch = before
    scratch += 100
    stdout().write("{b.n} {m.get("a")} {cs} {scratch}\n")
    return 0
