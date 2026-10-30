import Closeable from "@std/core.ms"

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit:
        return

fn dupe[T](xs: List[T]) Int:
    let ys = xs.reversed()
    return ys.length()

fn outer[U](xs: List[U]) Int:
    return dupe(xs)

fn f(ds: List[Door]) Int:
    let a = dupe(ds)  # error: `dupe` copies values of its type parameter `T`, so `T` cannot be the resource `Door`
    let b = outer(ds)  # error: `outer` copies values of its type parameter `U`
    let c = dupe([1, 2])
    return a + b + c
