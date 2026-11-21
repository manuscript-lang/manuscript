interface Src[T]:
    var fn next() T?!
    move fn close() Void!

type D:
    id: Int

fn var D.next() Int?!:
    return ok(none)

fn move D.close() Void!:
    return ok()

fn take(s: Src[Int]) Int:
    return 1

fn go(d: D) Int:
    return take(d)
