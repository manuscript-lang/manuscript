import keep, measure from "@std/test/bench.ms"
import Channel from "@std/io/channels.ms"
import TaskGroup, Task from "@std/concurrency/tasks.ms"
import Shared from "@std/concurrency/shared.ms"

fn produce(ch: Channel[Int, Unit]) Int:
    var c = ch
    for i in 0..100000:
        let _ = c.send(i)
    return 0

fn echo(ch: Channel[Int, Int]) Int:
    var c = ch

    while true:
        let r = c.receive().get(none)
        if r.is_none():
            break

        let _ = c.send(r.get(0))

    return 0

fn bump(var total: Int) Unit:
    total += 1

fn first_length(names: List[String]) Int:
    return names[0].length()

bench "tasks.spawn_results_1000":
    fn work() Result[Unit, Error]:
        var g = TaskGroup[Int]()
        for i in 0..1000:
            g.spawn(fn var ch: i * 2)

        let r = g.results().get([])
        return keep(r.length())

    try measure(1000, work)

bench "tasks.spawn_result_each_1000":
    fn work() Result[Unit, Error]:
        var g = TaskGroup[Int]()
        var n = 0

        for i in 0..1000:
            var t = g.spawn(fn var ch: i * 2)
            n += t.result().get(0)

        return keep(n)

    try measure(1000, work)

bench "tasks.spawn_then_result_5000":
    fn work() Result[Unit, Error]:
        var g = TaskGroup[Int]()
        var ts: List[Task[Int]] = []
        for i in 0..5000:
            ts.append(g.spawn(fn var ch: i))

        var n = 0
        for i in 0..ts.length():
            n += ts[i].result().get(0)
        return keep(n)

    try measure(5000, work)

bench "shared.update":
    fn work() Result[Unit, Error]:
        var box = Shared(0)
        for i in 0..200000:
            box += 1

        let total: Int = box
        return keep(total)

    try measure(200000, work)

bench "shared.call":
    fn work() Result[Unit, Error]:
        var box = Shared(0)
        for i in 0..200000:
            bump(var box)

        let total: Int = box
        return keep(total)

    try measure(200000, work)

bench "shared.read_call":
    fn work() Result[Unit, Error]:
        var box = Shared(["a-name-long-enough-for-the-heap"])
        var n = 0
        for i in 0..200000:
            n += first_length(box)
        return keep(n)

    try measure(200000, work)

bench "chan.stream_100k":
    fn work() Result[Unit, Error]:
        var g = TaskGroup[Int, Unit, Int]()
        var t = g.spawn(fn var ch: produce(ch))
        var n = 0

        while true:
            let r = t.channel.receive().get(none)
            if r.is_none():
                break

            n += r.get(0)

        return keep(n)

    try measure(100000, work)

bench "chan.pingpong_20k":
    fn work() Result[Unit, Error]:
        var g = TaskGroup[Int, Int, Int]()
        var t = g.spawn(fn var ch: echo(ch))
        var n = 0

        for i in 0..20000:
            let _ = t.channel.send(i)
            n += t.channel.receive().get(none).get(0)

        t.channel.close()
        return keep(n)

    try measure(20000, work)
