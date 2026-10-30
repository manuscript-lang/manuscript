import {keep, measure} from "@std/bench.ms"
import Channel from "@std/channels.ms"
import {TaskGroup, Task} from "@std/tasks.ms"
import new_lock from "@std/lock.ms"

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

bench "tasks.spawn_results_1000":
    fn work() Result[Unit, Error]:
        let g = TaskGroup[Int]()
        for i in 0..1000:
            g.spawn(fn ch: i * 2)

        let r = g.results().get([])
        return keep(r.length())

    try measure(1000, work)

bench "tasks.spawn_result_each_1000":
    fn work() Result[Unit, Error]:
        let g = TaskGroup[Int]()
        var n = 0

        for i in 0..1000:
            let t = g.spawn(fn ch: i * 2)
            n += t.result().get(0)

        return keep(n)

    try measure(1000, work)

bench "tasks.spawn_then_result_5000":
    fn work() Result[Unit, Error]:
        let g = TaskGroup[Int]()
        var ts: List[Task[Int]] = []
        for i in 0..5000:
            ts.append(g.spawn(fn ch: i))

        var n = 0
        for t in ts:
            n += t.result().get(0)
        return keep(n)

    try measure(5000, work)

bench "lock.uncontended":
    fn work() Result[Unit, Error]:
        let box = new_lock(0)

        for i in 0..200000:
            var g = box.lock()
            g.value += 1

        var g = box.lock()
        return keep(g.value)

    try measure(200000, work)

bench "chan.stream_100k":
    fn work() Result[Unit, Error]:
        let g = TaskGroup[Int, Unit, Int]()
        var t = g.spawn(fn ch: produce(ch))
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
        let g = TaskGroup[Int, Int, Int]()
        var t = g.spawn(fn ch: echo(ch))
        var n = 0

        for i in 0..20000:
            let _ = t.channel.send(i)
            n += t.channel.receive().get(none).get(0)

        t.channel.close()
        return keep(n)

    try measure(20000, work)
