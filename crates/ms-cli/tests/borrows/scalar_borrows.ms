import stdout from "@std/io/io.ms"

type Box:
    n: Int
    xs: List[Int]

fn bump(var b: Box) Unit:
    var _n = b.n
    _n += 1
    _n = _n * 2

impl Box:
    # A `var` copy of a scalar field in a `var fn` is a copy too (#2193).
    var fn mixed() Int:
        self.n = self.n + 1
        var z = self.n
        z = z * 10
        return z

export fn main() Int:
    var b = Box(n: 1, xs: [1])
    bump(var b)
    let mixed = b.mixed()

    var m = Map[String, Int]()
    m.add("a", 1)
    if var x = m["a"]?:
        x += 1

    var cs = [1, 2, 3]
    var _first = cs[0]
    _first += 10

    let before = b.n
    var scratch = before
    scratch += 100

    let _ = stdout().write("{b.n} {mixed} {m.get("a")} {cs} {scratch}\n")
    return 0
