import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit:
        return

interface Sink[T]:
    fn put(d: T) Int

type Bin[T]:
    count: Int

impl Sink[T] for Bin[T]:
    fn put(d: T) Int:
        var xs = [d]
        return xs.length()

fn wrap[T]() Sink[T]:
    return Bin[T](0)

fn f() Int:
    let s = wrap[Door]()  # error: `wrap` copies values of its type parameter `T`
    return s.put(Door(1))
