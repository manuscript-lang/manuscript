from "@std/io.ms" import stdout

type Box:
    name: String
    items: List[Int]

type Outer:
    inner: Box

impl Box:
    def list() -> ref List[Int]:
        return self.items

    def pick(first: Bool) -> ref List[Int]:
        if first:
            return self.items

        return self.items

impl Outer:
    def inside() -> ref Box:
        return self.inner

def first_of[T](xs: List[T]) -> ref T:
    return xs[0]

def forward(b: Box) -> ref List[Int]:
    return b.list()

def grow(var b: Box) -> Unit:
    var xs = b.list()
    xs.append(1)
    xs.append(2)

def grow_deep(var o: Outer) -> Unit:
    var xs = o.inside().list().clone()
    xs.append(7)

def copy_it(var b: Box) -> List[Int]:
    var xs = b.pick(True).clone()
    xs.append(100)
    return xs

def early(var b: Box, stop: Bool) -> Int:
    var xs = b.list()
    xs.append(5)
    if stop:
        return xs.length()

    xs.append(6)
    return xs.length()

export def main() -> Int:
    var b = Box(name: "a", items: [])
    grow(var b)

    let seen = forward(b)
    let n = b.list().length()
    var c = Box(name: "c", items: [0])
    let copy = copy_it(var c)
    var o = Outer(inner: Box(name: "o", items: [3]))
    grow_deep(var o)

    var e = Box(name: "e", items: [])
    let r1 = early(var e, True)
    let r2 = early(var e, False)
    let rows = [[1, 2], [3]]
    let row = first_of(rows)
    let _ = stdout().write(
        f"{b.items} {seen} {n} {c.items} {copy} {o.inner.items} {e.items} {r1} {r2} {row}\n"
    )
    return 0
