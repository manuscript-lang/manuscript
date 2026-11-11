import promise from "@std/concurrency/promise.ms"
import pipe, WriteStream from "@std/io/io.ms"

fn produce(var out: WriteStream[Int], base: Int) Unit!:
    out.write(base)?
    return out.close()

fn f() Unit!:
    var p = pipe[Int](4)
    var first = p.writer()
    var second = p.writer()
    a := promise(fn: ok(produce(var first, 1)?))
    b := promise(fn: ok(produce(var second, 2)?))
    a.wait()?
    b.wait()?
