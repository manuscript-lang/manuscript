from "@std/collections.ms" import range
from "@std/channels.ms" import Channel
from "@std/tasks.ms" import TaskGroup, Task
from "@std/shared.ms" import share
from "@std/sync.ms" import lock
from "./harness.ms" import bench

export def bench_conc() -> Unit:
    bench(
        "tasks.spawn_results_1000",
        1000,
        lambda () -> Int:
            with let g = TaskGroup[Int]():
                for i in range(0, 1000):
                    g.spawn(lambda ch: i * 2)

                let r = g.results().get([])
                return r.length()
    )
    bench(
        "tasks.spawn_result_each_1000",
        1000,
        lambda () -> Int:
            with let g = TaskGroup[Int]():
                var n = 0

                for i in range(0, 1000):
                    let t = g.spawn(lambda ch: i * 2)
                    n += t.result().get(0)

                return n
    )
    bench(
        "tasks.spawn_then_result_5000",
        5000,
        lambda () -> Int:
            with let g = TaskGroup[Int]():
                var ts: List[Task[Int]] = []
                for i in range(0, 5000):
                    ts.append(g.spawn(lambda ch: i))

                var n = 0
                for t in ts:
                    n += t.result().get(0)
                return n
    )

    bench(
        "lock.uncontended",
        200000,
        lambda () -> Int:
            let box = share(0)
            for i in range(0, 200000):
                with var g = lock(box):
                    g.value += 1
            with var g = lock(box):
                return g.value
    )

    bench(
        "chan.stream_100k",
        100000,
        lambda () -> Int:
            with let g = TaskGroup[Int, Unit, Int]():
                var t = g.spawn(lambda ch: produce(ch))
                var n = 0

                while True:
                    let r = t.channel.receive().get(none)
                    if r.is_none():
                        break

                    n += r.get(0)

                return n
    )
    bench(
        "chan.pingpong_20k",
        20000,
        lambda () -> Int:
            with let g = TaskGroup[Int, Int, Int]():
                var t = g.spawn(lambda ch: echo(ch))
                var n = 0

                for i in range(0, 20000):
                    t.channel.send(i)
                    n += t.channel.receive().get(none).get(0)

                t.channel.close()
                return n
    )

def produce(ch: Channel[Int, Unit]) -> Int:
    var c = ch
    for i in range(0, 100000):
        c.send(i)
    return 0

def echo(ch: Channel[Int, Int]) -> Int:
    var c = ch

    while True:
        let r = c.receive().get(none)
        if r.is_none():
            break

        c.send(r.get(0))

    return 0
