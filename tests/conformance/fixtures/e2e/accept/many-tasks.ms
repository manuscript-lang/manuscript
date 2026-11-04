// conform: tags=concurrency,stdlib-testing,testing,tier-core
// conform: phase=test
// conform: timeout=120
import expect_equal from "@std/test/test.ms"
import owned_promise, Promise, wait_all from "@std/concurrency/promise.ms"
import sleep, seconds, milliseconds from "@std/os/time.ms"
import Bytes from "@std/bytes.ms"
import read_file, remove, temporary_directory, write_file from "@std/os/fs.ms"

fn park(a: Int) Int!:
    try sleep(seconds(600)).wait()
    return ok(a)

// Fifty thousand promise tasks park at once: each costs a few kilobytes, so this takes a
// few hundred megabytes, and cancelling them all is linear.
test "fifty thousand parked promise tasks fit and cancel in bounded time":
    var promises: List[Promise[Int]] = []
    for i in 0..50000:
        promises.append(owned_promise[Int, Int](i, fn a: park(a)))
    try sleep(milliseconds(500)).wait()

    var done = 0
    for p in promises:
        if p.done(): done += 1
    try expect_equal(done, 0)
    for p in promises:
        p.cancel()

    var cancelled = 0

    for p in promises:
        match p.wait():
            ok(_): cancelled += 0
            error(_): cancelled += 1

    try expect_equal(cancelled, 50000)

// Forty thousand task-backed reads at once used to exhaust the process's memory mappings
// (two per task stack); slots carved from large regions cost none.
test "forty thousand concurrent file reads complete":
    let dir = try temporary_directory("many-tasks")
    let path = dir + "/read.txt"
    try write_file(path, "hello").wait()

    var reads: List[Promise[Bytes]] = []
    for unused in 0..40000:
        reads.append(read_file(path, none))

    let results = try wait_all(reads)
    var total = 0
    for data in results:
        total += data.length()
    try expect_equal(total, 200000)
    try remove(dir, recursive: true)
