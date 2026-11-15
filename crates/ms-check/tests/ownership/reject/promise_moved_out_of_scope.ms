import Promise, promise from "@std/concurrency/promise.ms"

type Acc:
    p: Promise[Int]

fn assigned() Int!:
    var o: Promise[Int]? = none
    for i in 0..2:
        xs := [1, 2, 3]
        p := promise[Int](fn: ok(xs[0] + i))  // error: this promise reads `xs`, which ends before `o` does
        o = p
    return ok(0)

fn built() Int!:
    var a: Acc? = none
    for i in 0..2:
        xs := [1, 2, 3]
        p := promise[Int](fn: ok(xs[0] + i))  // error: this promise reads `xs`, which ends before `a` does
        a = Acc(p)
    return ok(0)

fn wrapped() Int!:
    var accs: List[Acc] = []
    for i in 0..2:
        xs := [1, 2, 3]
        accs.append(Acc(promise(fn: ok(xs[0] + i))))  // error: this promise reads `xs`, which ends before `accs` does
    return ok(0)
