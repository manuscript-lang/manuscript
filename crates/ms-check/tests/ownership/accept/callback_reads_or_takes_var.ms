import Shared from "@std/concurrency/shared.ms"

type Counter:
    values: List[Int]

type Tally:
    n: Int

impl Counter:
    var fn bump() Unit:
        self.values.append(1)

    fn count_after(after: fn() Unit) Int:
        after()
        return self.values.length()

    var fn each_bump(step: fn(var Counter) Unit) Unit:
        step(var self)

fn reads() Int:
    var shared = Shared(Counter([]))
    let view = shared
    var seen = 0
    let n = shared.count_after(fn() Unit: seen = view.values.length())
    return n + seen

fn other_kind() Int:
    var shared = Shared(Counter([]))
    var tally = Shared(Tally(0))
    return shared.count_after(fn() Unit: tally.n += 1)

fn takes_var() Unit:
    var shared = Shared(Counter([]))
    shared.each_bump(fn var counter: counter.bump())
