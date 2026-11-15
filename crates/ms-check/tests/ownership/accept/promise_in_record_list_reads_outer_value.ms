import Promise, promise from "@std/concurrency/promise.ms"

type Acc:
    ps: List[Promise[Int]]

fn demo() Int!:
    xs := [1, 2, 3]
    var acc = Acc([])
    for i in 0..3:
        acc.ps.append(promise(fn: ok(xs.length() + i)))
    var total = 0
    for p in acc.ps:
        total += p.wait()?
    return ok(total)
