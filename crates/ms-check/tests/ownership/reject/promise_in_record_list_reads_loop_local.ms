import Promise, promise from "@std/concurrency/promise.ms"

type Acc:
    ps: List[Promise[Int]]

fn demo() Int!:
    var acc = Acc([])
    for i in 0..3:
        s := [f"value-{i}", "a"]
        acc.ps.append(promise(fn: ok(s.length())))  // error: this promise reads `s`, which ends before `acc` does
    return ok(acc.ps.length())
