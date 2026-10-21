import stdout from "@std/io.ms"

type Box:
    name: String
    items: List[Int]

type Outer:
    inner: Box

impl Box:
    fn list() List[Int]:
        return self.items

    fn pick(first: Bool) List[Int]:
        if first:
            return self.items
        return [9]

impl Outer:
    fn inside() Box:
        return self.inner

fn first_of[T](xs: List[T]) T:
    return xs[0]

fn forward(b: Box) List[Int]:
    return b.list()

fn grow(var b: Box) Unit:
    var xs = b.list()
    xs.append(1)
    xs.append(2)

fn grow_deep(var o: Outer) Unit:
    var xs = o.inside().list()
    xs.append(7)

fn copy_it(var b: Box) List[Int]:
    var xs = b.pick(true)
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
    stdout().write("{b.items} {seen} {n} {c.items} {copy} {o.inner.items} {e.items} {r1} {r2} {row}\n")
    return 0
