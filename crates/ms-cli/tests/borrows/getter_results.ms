import stdout from "@std/io.ms"

type Box:
    name: String
    items: List[Int]

type Outer:
    inner: Box

impl Box:
    fn list() ref List[Int]:
        return self.items

    fn pick(first: Bool) ref List[Int]:
        if first:
            return self.items

        return self.items

impl Outer:
    fn inside() ref Box:
        return self.inner

fn first_of[T](xs: List[T]) ref T:
    return xs[0]

fn forward(b: Box) ref List[Int]:
    return b.list()

fn grow(var b: Box) Unit:
    var xs = b.list()
    xs.append(1)
    xs.append(2)

fn grow_deep(var o: Outer) Unit:
    var xs = o.inside().list().clone()
    xs.append(7)

fn copy_it(var b: Box) List[Int]:
    var xs = b.pick(true).clone()
    xs.append(100)
    return xs

fn early(var b: Box, stop: Bool) Int:
    var xs = b.list()
    xs.append(5)
    if stop:
        return xs.length()

    xs.append(6)
    return xs.length()

export fn main() Int:
    var b = Box(name: "a", items: [])
    grow(var b)

    let seen = forward(b)
    let n = b.list().length()
    var c = Box(name: "c", items: [0])
    let copy = copy_it(var c)
    var o = Outer(inner: Box(name: "o", items: [3]))
    grow_deep(var o)

    var e = Box(name: "e", items: [])
    let r1 = early(var e, true)
    let r2 = early(var e, false)
    let rows = [[1, 2], [3]]
    let row = first_of(rows)
    let _ = stdout().write(
        "{b.items} {seen} {n} {c.items} {copy} {o.inner.items} {e.items} {r1} {r2} {row}\n"
    )
    return 0
