import Closeable from "@std/core.ms"

type Door:
    id: Int

fn var Door.close() Unit!:
    return ok(unit)

fn dupe[T](xs: List[T]) Int:
    ys := xs.reversed()  // error: reversed requires T to be Clonable
    return ys.length()

fn outer[U](xs: List[U]) Int:
    return dupe(xs)

fn f(ds: List[Door]) Int:
    a := dupe(ds)
    b := outer(ds)
    c := dupe([1, 2])
    return a + b + c
