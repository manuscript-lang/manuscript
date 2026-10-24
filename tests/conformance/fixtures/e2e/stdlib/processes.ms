# conform: tags=closures,with-cleanup,stdlib-channels,stdlib-processes,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
from "@std/channels.ms" import Channel, ChannelError
from "@std/core.ms" import panic
from "@std/process.ms" import CommandError, Stdio
from "@std/processes.ms" import ProcessError, ProcessGroup
from "@std/testing.ms" import expect_equal, expect_error, expect_ok

type Job:
    name: String
    sizes: List[Int]

def square_all(ch: Channel[Int, Int]) -> Result[Int, ChannelError]:
    var c = ch
    var count = 0

    while True:
        if let n = try c.receive():
            try c.send(n * n)
            count += 1
        else:
            return ok(count)

    return ok(count)

def describe(ch: Channel[Unit, Unit]) -> Job:
    return Job(name: "child", sizes: [1, 2, 3])

def quiet(ch: Channel[Unit, Unit]) -> Unit:
    return ()

def crash(ch: Channel[Unit, Unit]) -> Unit:
    panic("the child faults on purpose")

def echo_jobs(ch: Channel[Job, Job]) -> Int:
    var c = ch
    var count = 0
    while True:
        match c.receive():
            case ok(next):
                if let job = next:
                    if c.send(Job(name: job.name + "!", sizes: job.sizes.clone())).is_error():
                        return -1
                    count += 1
                else:
                    return count
            case error(_):
                return -2
    return count

def report(ch: Channel[Int, Unit]) -> Int:
    var c = ch
    for n in [10, 20, 30]:
        if c.send(n).is_error():
            return -1
    return 3

test "a child process answers each message in order":
    with ProcessGroup[Result[Int, ChannelError], Int, Int]() as group:
        var child = group.spawn(square_all) | try expect_ok
        for n in [1, 2, 3]:
            child.channel.send(n) | try expect_ok
            child.channel.receive() | try expect_ok | try expect_equal(some(n * n))
        child.channel.close()
        let answered = child.result() | try expect_ok
        answered | try expect_ok | try expect_equal(3)

test "records cross in both directions":
    with ProcessGroup[Int, Job, Job]() as group:
        var child = group.spawn(echo_jobs) | try expect_ok
        child.channel.send(Job(name: "a", sizes: [4, 5])) | try expect_ok
        let back = child.channel.receive() | try expect_ok
        if let job = back:
            try expect_equal(job.name, "a!")
            try expect_equal(job.sizes, [4, 5])
        else:
            try expect_equal("no reply", "a reply")
        child.channel.close()
        child.result() | try expect_ok | try expect_equal(1)

test "the parent reads what a finished child sent, then the end":
    with ProcessGroup[Int, Unit, Int]() as group:
        var child = group.spawn(report) | try expect_ok
        child.channel.receive() | try expect_ok | try expect_equal(some(10))
        child.channel.receive() | try expect_ok | try expect_equal(some(20))
        child.channel.receive() | try expect_ok | try expect_equal(some(30))
        child.channel.receive() | try expect_ok | try expect_equal(none)
        child.result() | try expect_ok | try expect_equal(3)
        child.wait() | try expect_ok | try expect_equal(0)

test "results come back in start order":
    with ProcessGroup[Job]() as group:
        let first = group.spawn(describe) | try expect_ok
        let second = group.spawn(describe) | try expect_ok
        let all = group.results() | try expect_ok
        try expect_equal(all.length(), 2)
        try expect_equal(all[1].name, "child")
        try expect_equal(all[0].sizes, [1, 2, 3])

test "a Unit result crosses":
    with ProcessGroup[Unit]() as group:
        var child = group.spawn(quiet) | try expect_ok
        child.result() | try expect_ok

test "a child that faults is data, not a parent fault":
    with ProcessGroup[Unit]() as group:
        var child = group.spawn(crash, stderr: Stdio.Null) | try expect_ok
        child.result() | try expect_error | try expect_equal(ProcessError.Exited(70))
        let refused = child.channel.send(()) | try expect_error

test "a piped standard stream is not offered":
    with ProcessGroup[Unit]() as group:
        group.spawn(quiet, stdout: Stdio.Pipe) | try expect_error | try expect_equal(CommandError.InvalidInput)

test "process errors describe themselves":
    try expect_equal(ProcessError.Exited(70).message(), "process: exited with status 70")
    try expect_equal(ProcessError.Broken("bad frame").message(), "process: broken: bad frame")
