import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

interface Sink[T]:
    fn put(d: T) Int

type Bin[T]:
    count: Int

impl Sink[T] for Bin[T]:
    fn put(d: T) Int:
        var xs = [d]
        return xs.length()

fn wrap[T]() Sink[T]:
    return Bin[T](0)  # error: so it copies values of `T`, which may be a resource; declare `T: Clonable`

fn f() Int:
    let s = wrap[Door]()
    return s.put(Door(1))
