import Closeable from "@std/core.ms"

type Door:
    n: Int

fn var Door.close() Void!:
    return ok()

interface Sink[T]:
    fn put(d: T) Int

type Bin[T]:
    count: Int

fn Bin[T].put(d: T) Int:
    var xs = [d]
    return xs.length()

fn wrap[T]() Sink[T]:
    return Bin[T](0)  // error: keeps its `d`, which the interface borrows

fn f() Int:
    s := wrap[Door]()
    return s.put(Door(1))
