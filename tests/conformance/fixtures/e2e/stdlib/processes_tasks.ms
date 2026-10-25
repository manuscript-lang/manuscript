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
    with let procs = ProcessGroup[Int, Unit, Int]():
        var child = procs.spawn(talker).get()
        let reader = child.channel.clone()

        with let tasks = TaskGroup[Int]():
            tasks.spawn(lambda ch: read_all(reader.clone()))

            # The receiver is the one reading the pipe by now, so `result` waits for it.
            sleep(duration(150000000))
            try expect_equal(child.result().get(-1), 42)
            try expect_equal(tasks.results().get([]), [3])

test "a task cancelled in a channel read releases the link":
    with let group = ProcessGroup[Int, Unit, Int]():
        var child = group.spawn(late).get()
        let reader = child.channel.clone()

        with let tasks = TaskGroup[Int](timeout: some(duration(50000000))):
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
    with let group = TaskGroup[Int](timeout: some(duration(200000000))):
        let t = group.spawn(lambda ch: run_long())
        try expect_equal(t.result().is_ok(), False)

    sleep(duration(200000000))
    try expect_equal(long_alive(), False)

def wait_long() -> Int:
    let child = commands().spawn(long_program(), long_args()).get()
    return child.wait().get(-1)

test "cancelling a task inside Subprocess.wait kills the child":
    with let group = TaskGroup[Int](timeout: some(duration(200000000))):
        let t = group.spawn(lambda ch: wait_long())
        try expect_equal(t.result().is_ok(), False)

    sleep(duration(200000000))
    try expect_equal(long_alive(), False)

# The child belongs to the task's closure, not to a local of its frames, so the unwind pass has no
# value to drop: only Subprocess.wait's own cleanup stops it.
test "cancelling a task inside Subprocess.wait stops a child the task was handed":
    let child = commands().spawn(long_program(), long_args()).get()
    with let group = TaskGroup[Int](timeout: some(duration(200000000))):
        let t = group.spawn(lambda ch: child.wait().get(-1))
        try expect_equal(t.result().is_ok(), False)

    sleep(duration(200000000))
    try expect_equal(long_alive(), False)

test "the liveness check sees a live child":
    with let child = try commands().spawn(long_program(), long_args()):
        try expect_equal(long_alive(), True)

def slow_sum(ch: Channel[Unit, Int]) -> Int:
    var c = ch
    sleep(duration(200000000))

    var total = 0

    while True:
        let got = c.receive()
        if got.is_error():
            return -1
        if got.get().is_none():
            return total

        total += got.get().get()

    return total

def send_many(c: Channel[Int, Unit], n: Int) -> Int:
    var cc = c
    for i in 0..n:
        if cc.send(1).is_error():
            return -1
    return n

test "two tasks send to the same child while its pipe is full":
    with let group = ProcessGroup[Int, Int, Unit]():
        var child = group.spawn(slow_sum).get()
        let a = child.channel.clone()
        let b = child.channel.clone()

        with let tasks = TaskGroup[Int]():
            tasks.spawn(lambda ch: send_many(a.clone(), 20000))
            tasks.spawn(lambda ch: send_many(b.clone(), 20000))
            try expect_equal(tasks.results().get([]), [20000, 20000])

        child.channel.close()
        try expect_equal(child.result().get(-1), 40000)

test "two tasks receive from the same child":
    with let group = ProcessGroup[Int, Unit, Int]():
        var child = group.spawn(talker).get()
        let a = child.channel.clone()
        let b = child.channel.clone()

        with let tasks = TaskGroup[Int]():
            tasks.spawn(lambda ch: read_all(a.clone()))
            tasks.spawn(lambda ch: read_all(b.clone()))

            let got = tasks.results().get([])
            try expect_equal(got.length(), 2)
            try expect_equal(got[0] + got[1], 3)

        try expect_equal(child.result().get(-1), 42)
