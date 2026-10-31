# conform: tags=closures,scope-cleanup,stdlib-channels,stdlib-processes,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
import Channel, ChannelError from "@std/channels.ms"
import panic from "@std/core.ms"
import read_line, stderr, stdin, stdout from "@std/io.ms"
import Stdio from "@std/process.ms"
import ProcessError, ProcessGroup from "@std/processes.ms"
import expect_equal, expect_error, expect_ok from "@std/test.ms"

type Job:
    name: String
    sizes: List[Int]

fn square_all(ch: Channel[Int, Int]) Int!ChannelError:
    var c = ch
    var count = 0

    while true:
        if let n = try c.receive():
            try c.send(n * n)
            count += 1
        else:
            return ok(count)

    return ok(count)

fn describe(ch: Channel[Unit, Unit]) Job:
    return Job(name: "child", sizes: [1, 2, 3])

fn quiet(ch: Channel[Unit, Unit]) Unit:
    return unit

fn shout(ch: Channel[Unit, Unit]) Int:
    match read_line(stdin()):
        ok(next):
            let text = next.get("")
            if stdout().write(text + "!\n").is_error():
                return -1
            if stderr().write("warn\n").is_error():
                return -2

            return text.length()
        error(_):
            return -3

    return -4

fn crash(ch: Channel[Unit, Unit]) Unit:
    panic("the child faults on purpose")

fn echo_jobs(ch: Channel[Job, Job]) Int:
    var c = ch
    var count = 0

    while true:
        match c.receive():
            ok(next):
                if let job = next:
                    if c.send(
                        Job(
                            name: job.name + "!", sizes: job.sizes.clone()
                        )
                    ).is_error():
                        return -1

                    count += 1
                else:
                    return count
            error(_):
                return -2

    return count

fn report(ch: Channel[Int, Unit]) Int:
    var c = ch
    for n in [10, 20, 30]:
        if c.send(n).is_error():
            return -1
    return 3

test "a child process answers each message in order":
    let group = ProcessGroup[Int!ChannelError, Int, Int]()
    var child = group.spawn(square_all) | try expect_ok

    for n in [1, 2, 3]:
        child.channel.send(n) | try expect_ok
        child.channel.receive() | try expect_ok | try expect_equal((n * n))

    child.channel.close()

    let answered = child.result() | try expect_ok
    answered | try expect_ok | try expect_equal(3)

test "records cross in both directions":
    let group = ProcessGroup[Int, Job, Job]()
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
    let group = ProcessGroup[Int, Unit, Int]()
    var child = group.spawn(report) | try expect_ok
    child.channel.receive() | try expect_ok | try expect_equal(10)
    child.channel.receive() | try expect_ok | try expect_equal(20)
    child.channel.receive() | try expect_ok | try expect_equal(30)
    child.channel.receive() | try expect_ok | try expect_equal(none)
    child.result() | try expect_ok | try expect_equal(3)
    child.wait() | try expect_ok | try expect_equal(0)

test "results come back in start order":
    let group = ProcessGroup[Job]()
    let _first = group.spawn(describe) | try expect_ok
    let _second = group.spawn(describe) | try expect_ok
    let all = group.results() | try expect_ok
    try expect_equal(all.length(), 2)
    try expect_equal(all[1].name, "child")
    try expect_equal(all[0].sizes, [1, 2, 3])

test "a group forgets a closed process":
    let group = ProcessGroup[Job]()
    var first = group.spawn(describe) | try expect_ok
    let _second = group.spawn(describe) | try expect_ok
    let kept = first.result() | try expect_ok
    try expect_equal(kept.name, "child")
    first.close()
    first.close()

    let all = group.results() | try expect_ok
    try expect_equal(all.length(), 1)

test "a Unit result crosses":
    let group = ProcessGroup[Unit]()
    var child = group.spawn(quiet) | try expect_ok
    child.result() | try expect_ok

test "a child that faults is data, not a parent fault":
    let group = ProcessGroup[Unit]()
    var child = group.spawn(crash, stderr: Stdio.Null) | try expect_ok
    child.result() | try expect_error | try expect_equal(ProcessError.Exited(67))

    let _refused = child.channel.send(unit) | try expect_error

test "piped standard streams reach the parent":
    let group = ProcessGroup[Int]()
    var child = group.spawn(
        shout, stdin: Stdio.Pipe, stdout: Stdio.Pipe, stderr: Stdio.Pipe
    ) | try expect_ok
    try child.stdin().write("hi\n")
    child.stdin().close()

    let out = try read_line(child.stdout())
    try expect_equal(out.get(""), "hi!")

    let err = try read_line(child.stderr())
    try expect_equal(err.get(""), "warn")
    child.result() | try expect_ok | try expect_equal(2)

test "a stream that is not piped is closed":
    let group = ProcessGroup[Unit]()
    var child = group.spawn(quiet, stdout: Stdio.Null) | try expect_ok
    try expect_equal(child.stdout().read().is_ok(), false)
    try expect_equal(child.stdin().write("x").is_ok(), false)
    child.result() | try expect_ok

test "process errors describe themselves":
    try expect_equal(
        ProcessError.Exited(67).message(), "process: exited with status 67"
    )
    try expect_equal(
        ProcessError.Broken("bad frame").message(), "process: broken: bad frame"
    )
