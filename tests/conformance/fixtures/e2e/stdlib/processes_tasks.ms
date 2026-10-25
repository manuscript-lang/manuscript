# conform: tags=closures,with-cleanup,stdlib-channels,stdlib-processes,stdlib-tasks,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
from "@std/channels.ms" import Channel
from "@std/process.ms" import commands, os_type
from "@std/processes.ms" import ProcessGroup
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal
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

            # The receiver is the one reading the pipe by now, so `result` waits for it.
            sleep(duration(150000000))
            try expect_equal(child.result().get(-1), 42)
            try expect_equal(tasks.results().get([]), [3])

test "a task cancelled in a channel read releases the link":
    with ProcessGroup[Int, Unit, Int]() as group:
        var child = group.spawn(late).get()
        let reader = child.channel.clone()

        with TaskGroup[Int](timeout: some(duration(50000000))) as tasks:
            tasks.spawn(lambda ch: first(reader.clone()))
            try expect_equal(tasks.wait().is_error(), True)

        try expect_equal(child.result().get(-1), 42)

def long_program() -> String:
    if os_type() == "windows":
        return "ping"

    return "sleep"

def long_args() -> List[String]:
    if os_type() == "windows":
        return ["-n", "31", "127.0.0.77"]

    return ["30.717"]

def run_long() -> Int:
    let out = commands().run(long_program(), long_args())
    return out.get().exit_code

# Whether the long-running child is alive: a process listing for ping on Windows, where nothing
# else in the run starts one, and the command line on other systems.
def long_alive() -> Bool:
    if os_type() == "windows":
        let listed = commands().run("tasklist", ["/FI", "IMAGENAME eq ping.exe", "/NH"])
        return listed.get().stdout.contains("PING.EXE".to_bytes())

    let found = commands().run("pgrep", ["-f", "sleep 30.717"])
    return found.get().exit_code == 0

test "cancelling a task inside commands().run kills the child":
    with TaskGroup[Int](timeout: some(duration(200000000))) as group:
        let t = group.spawn(lambda ch: run_long())
        try expect_equal(t.result().is_ok(), False)

    sleep(duration(200000000))
    try expect_equal(long_alive(), False)

test "the liveness check sees a live child":
    with try commands().spawn(long_program(), long_args()) as child:
        try expect_equal(long_alive(), True)
