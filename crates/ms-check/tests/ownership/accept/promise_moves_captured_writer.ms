import promise from "@std/concurrency/promise.ms"
import pipe, WriteStream from "@std/io/io.ms"

fn produce(var out: WriteStream[Int], base: Int) Unit!:
    try out.write(base)
    return out.close()

fn f() Unit!:
    var p = pipe[Int](4)
    var first = p.writer()
    var second = p.writer()
    let a = promise(fn: ok(try produce(var first, 1)))
    let b = promise(fn: ok(try produce(var second, 2)))
    try a.wait()
    try b.wait()
    return ok(unit)
