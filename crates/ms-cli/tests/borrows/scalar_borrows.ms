from "@std/io.ms" import stdout

type Box:
    n: Int
    xs: List[Int]

def bump(var b: Box) -> Unit:
    var _n = b.n
    _n += 1
    _n = _n * 2

export def main() -> Int:
    var b = Box(n: 1, xs: [1])
    bump(var b)

    var m = Map[String, Int]()
    m.add("a", 1)
    if var x = m.get("a"):
        x += 1

    var cs = [1, 2, 3]
    var _first = cs[0]
    _first += 10

    let before = b.n
    var scratch = before
    scratch += 100

    let _ = stdout().write(f"{b.n} {m.get("a")} {cs} {scratch}\n")
    return 0
