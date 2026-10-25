# conform: tags=closures,with-cleanup,stdlib-channels,stdlib-processes,stdlib-tasks,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
from "@std/channels.ms" import Channel
from "@std/processes.ms" import ProcessGroup
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal, expect_ok
from "@std/time.ms" import duration, sleep

def talker(ch: Channel[Int, Unit]) -> Int:
    var c = ch
    for i in 0..3:
        sleep(duration(20000000))
        c.send(i)
    return 42

def late(ch: Channel[Int, Unit]) -> Int:
    sleep(duration(300000000))
    return 42

def read_all(c: Channel[Unit, Int]) -> Int:
    var cc = c
    var n = 0
    while True:
        let got = cc.receive()
        if got.is_error():
            return -1
        if got.get().is_none():
            return n
        n += 1
    return n

def first(c: Channel[Unit, Int]) -> Int:
    var cc = c
    let got = cc.receive()
    return 0

test "result waits while another task receives from the same child":
    with ProcessGroup[Int, Unit, Int]() as procs:
        var child = procs.spawn(talker).get()
        let reader = child.channel.clone()
        with TaskGroup[Int]() as tasks:
            tasks.spawn(lambda ch: read_all(reader.clone()))
            expect_equal(child.result().get(-1), 42)
            expect_equal(tasks.results().get([]), [3])

test "a task cancelled in a channel read releases the link":
    with ProcessGroup[Int, Unit, Int]() as group:
        var child = group.spawn(late).get()
        let reader = child.channel.clone()
        with TaskGroup[Int](timeout: some(duration(50000000))) as tasks:
            tasks.spawn(lambda ch: first(reader.clone()))
            expect_equal(tasks.wait().is_error(), True)
        expect_equal(child.result().get(-1), 42)
