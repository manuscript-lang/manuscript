import pipe, stdout, ReadStream, WriteStream from "@std/io/io.ms"
import promise from "@std/concurrency/promise.ms"

fn fill(var out: WriteStream[Int], from: Int, count: Int) Unit!:
    for i in from..from + count:
        try out.write(i)
    try out.flush()
    return out.close()

fn stage(var input: ReadStream[Int], var out: WriteStream[Int]) Unit!:
    for v in input:
        try out.write(v + 1)
    try out.flush()
    return out.close()

fn run() Unit!:
    var p = pipe[Int](64)
    var q = pipe[Int](64)
    var w1 = p.writer()
    var pr = p.reader()
    var qw = q.writer()
    var input = q.reader()
    try p.close()
    try q.close()

    let a = promise(fn: fill(var w1, 0, 1000000))
    let st = promise(fn: stage(var pr, var qw))
    var sum = 0
    var n = 0

    for v in input:
        sum += v
        n += 1

    try a.wait()
    try st.wait()
    try stdout().write("{n} {sum}\n")
    return ok(unit)

export fn main() Int:
    run().get()
    return 0
