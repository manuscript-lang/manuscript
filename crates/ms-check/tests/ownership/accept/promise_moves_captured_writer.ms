import promise from "@std/concurrency/promise.ms"
import pipe, WriteStream from "@std/io/io.ms"

fn produce(var out: WriteStream[Int], base: Int) Void!:
    out.write(base)?
    return out.flush()

fn f() Void!:
    var p = pipe[Int](4)
    var first = p.writer()
    var second = p.writer()
    a := promise(fn: ok(produce(first, 1)?))
    b := promise(fn: ok(produce(second, 2)?))
    a.wait()?
    b.wait()?
