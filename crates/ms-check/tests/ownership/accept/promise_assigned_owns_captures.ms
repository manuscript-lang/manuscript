import Promise, promise from "@std/concurrency/promise.ms"

type Acc:
    p: Promise[Int]

fn assigned() Int!:
    var o: Promise[Int]? = none
    for i in 0..2:
        xs := [1, 2, 3]
        o = promise[Int](fn: ok(xs[0] + i))
    if p := o:
        return p.wait()
    return ok(0)

fn built() Int!:
    var a = Acc(promise[Int](fn: ok(1)))
    for i in 0..2:
        xs := [1, 2, 3]
        a = Acc(promise[Int](fn: ok(xs[0] + i)))
    return a.p.wait()
