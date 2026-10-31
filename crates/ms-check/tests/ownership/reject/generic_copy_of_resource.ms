import Closeable from "@std/core.ms"

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit:
        return

fn dupe[T](xs: List[T]) Int:
    let ys = xs.reversed()  # error: reversed requires T to be Clonable
    return ys.length()

fn outer[U](xs: List[U]) Int:
    return dupe(xs)

fn f(ds: List[Door]) Int:
    let a = dupe(ds)
    let b = outer(ds)
    let c = dupe([1, 2])
    return a + b + c
