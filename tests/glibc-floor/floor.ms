// Runs on the oldest glibc that Linux programs support (2.28). CI builds it on a current host and runs it
// in an AlmaLinux 8 container: threads, the resolver pool, file metadata, child processes, entropy and libm
// all reach glibc through the versions the link-time stubs bind.
import (
    stdout from "@std/io/io.ms",
    stat from "@std/os/fs.ms",
    run from "@std/os/process.ms",
    secure_int from "@std/random.ms",
    exp, hypot, log, pow from "@std/math/math.ms",
    lookup from "@std/net/net.ms",
    nanoseconds, sleep from "@std/time.ms",
    promise from "@std/concurrency/promise.ms",
)

fn square(n: Int) Int:
    return n * n

fn main() Unit:
    squared := promise(fn: ok(square(12))).wait().get(-1)
    file := stat("/etc/hosts", follow_links: true).is_ok()
    child := run("true", []).wait().is_ok()
    entropy := secure_int(0, max_exclusive: 10).is_ok()
    hosts := lookup("localhost").is_ok()
    _ := sleep(nanoseconds(1000000)).wait()
    math := pow(2.0, 10.0) + exp(0.0) + log(1.0) + hypot(3.0, 4.0)
    stdout().write("{squared} {file} {child} {entropy} {hosts} {math}\n").get()
