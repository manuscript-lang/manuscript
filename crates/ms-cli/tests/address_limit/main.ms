import Promise, promise from "@std/concurrency/promise.ms"
import milliseconds, sleep from "@std/time.ms"

fn work(i: Int) Int!:
    big := "x".repeat(2000000)
    void sleep(milliseconds(1)).wait()
    return ok(big.length() % 7 + i % 3)

fn main() Void!:
    var total = 0
    for round in 0..4:
        var tasks: List[Promise[Int]] = []
        for i in 0..1000: tasks.append(promise(fn: work(i)))
        for task in tasks: total += task.wait()?
    if total <= 0: return error(Error("no work done"))
