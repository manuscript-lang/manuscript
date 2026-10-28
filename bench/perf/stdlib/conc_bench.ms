from "@std/bench.ms" import keep, measure
from "@std/channels.ms" import Channel
from "@std/tasks.ms" import TaskGroup, Task
from "@std/shared.ms" import share
from "@std/sync.ms" import lock

def produce(ch: Channel[Int, Unit]) -> Int:
    var c = ch
    for i in 0..100000:
        let _ = c.send(i)
    return 0

def echo(ch: Channel[Int, Int]) -> Int:
    var c = ch

    while True:
        let r = c.receive().get(none)
        if r.is_none():
            break

        let _ = c.send(r.get(0))

    return 0

bench "tasks.spawn_results_1000":
    def work() -> Result[Unit, Error]:
        let g = TaskGroup[Int]()
        for i in 0..1000:
            g.spawn(lambda ch: i * 2)

        let r = g.results().get([])
        return keep(r.length())

    try measure(1000, work)

bench "tasks.spawn_result_each_1000":
    def work() -> Result[Unit, Error]:
        let g = TaskGroup[Int]()
        var n = 0

        for i in 0..1000:
            let t = g.spawn(lambda ch: i * 2)
            n += t.result().get(0)

        return keep(n)

    try measure(1000, work)

bench "tasks.spawn_then_result_5000":
    def work() -> Result[Unit, Error]:
        let g = TaskGroup[Int]()
        var ts: List[Task[Int]] = []
        for i in 0..5000:
            ts.append(g.spawn(lambda ch: i))

        var n = 0
        for t in ts:
            n += t.result().get(0)
        return keep(n)

    try measure(5000, work)

bench "lock.uncontended":
    def work() -> Result[Unit, Error]:
        let box = share(0)

        for i in 0..200000:
            var g = lock(box)
            g.value += 1

        var g = lock(box)
        return keep(g.value)

    try measure(200000, work)

bench "chan.stream_100k":
    def work() -> Result[Unit, Error]:
        let g = TaskGroup[Int, Unit, Int]()
        var t = g.spawn(lambda ch: produce(ch))
        var n = 0

        while True:
            let r = t.channel.receive().get(none)
            if r.is_none():
                break

            n += r.get(0)

        return keep(n)

    try measure(100000, work)

bench "chan.pingpong_20k":
    def work() -> Result[Unit, Error]:
        let g = TaskGroup[Int, Int, Int]()
        var t = g.spawn(lambda ch: echo(ch))
        var n = 0

        for i in 0..20000:
            let _ = t.channel.send(i)
            n += t.channel.receive().get(none).get(0)

        t.channel.close()
        return keep(n)

    try measure(20000, work)
