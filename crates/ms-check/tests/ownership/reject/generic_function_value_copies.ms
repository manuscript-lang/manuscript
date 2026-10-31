import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit:
        return

fn keep[T](x: T) List[T]:
    return [x]

fn apply[T](xs: List[T], f: fn(T) List[T]) Int:
    var n = 0
    for x in xs:
        n += f(x).length()
    return n

fn outer[T](xs: List[T]) Int:
    return apply(xs, keep[T])

fn g() Int:
    return outer([Door(1)])  # error: `outer` copies values of its type parameter `T`
