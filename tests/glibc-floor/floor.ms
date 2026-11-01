# Runs on the oldest glibc that Linux programs support (2.28). CI builds it on a current host and runs it
# in an AlmaLinux 8 container: threads, the resolver pool, file metadata, child processes, entropy and libm
# all reach glibc through the versions the link-time stubs bind.
import stdout from "@std/io/io.ms"
import stat from "@std/os/fs.ms"
import run from "@std/os/process.ms"
import secure_int from "@std/os/random.ms"
import exp, hypot, log, pow from "@std/math/math.ms"
import lookup from "@std/net/net.ms"
import nanoseconds, sleep from "@std/os/time.ms"
import WorkerGroup, WorkerError, worker_channel from "@std/concurrency/workers.ms"

fn squares() Unit:
    var ch = worker_channel[Int, Int]()
    if let n = ch.receive().get(none):
        let _ = ch.send(n * n)

fn ask(group: WorkerGroup[Int, Int], value: Int) Int!WorkerError:
    var worker = try group.spawn(squares)
    let _ = worker.channel.send(value)
    var answer = -1
    if let got = worker.channel.receive().get(none):
        answer = got
    try worker.wait()
    return ok(answer)

export fn main() Int:
    let group = WorkerGroup[Int, Int]()
    let squared = ask(group, 12).get(-1)
    let file = stat("/etc/hosts", follow_links: true).is_ok()
    let child = run("true", []).is_ok()
    let entropy = secure_int(0, max_exclusive: 10).is_ok()
    let hosts = lookup("localhost").is_ok()
    sleep(nanoseconds(1000000))

    let math = pow(2.0, 10.0) + exp(0.0) + log(1.0) + hypot(3.0, 4.0)
    stdout().write("{squared} {file} {child} {entropy} {hosts} {math}\n").get()
    return 0
