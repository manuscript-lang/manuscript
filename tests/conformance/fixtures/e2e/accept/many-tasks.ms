// conform: tags=stdlib-promise,stdlib-fs,stdlib-testing,testing,tier-io
// conform: phase=test
// conform: timeout=120
import (
	Bytes from "@std/bytes.ms",
	Promise, owned_task, wait_all from "@std/concurrency/promise.ms",
	read_file, remove, temporary_directory, write_file from "@std/os/fs.ms",
	expect_equal from "@std/test/test.ms",
	milliseconds, seconds, sleep from "@std/time.ms",
)

fn park(a: Int) Int!:
	sleep(seconds(600)).wait()?
	return ok(a)

// Fifty thousand promise tasks park at once: each costs a few kilobytes, so this takes a
// few hundred megabytes, and cancelling them all is linear.
test "fifty thousand parked promise tasks fit and cancel in bounded time":
	var promises: List[Promise[Int]] = []
	for i in 0..50000:
		promises.append(owned_task[Int](fn: park(i)))
	sleep(milliseconds(500)).wait()?

	var done = 0
	for p in promises:
		if p.done(): done += 1
	expect_equal(done, 0)?
	for p in promises:
		p.cancel()

	var cancelled = 0

	for p in promises:
		match p.wait():
			ok(_): cancelled += 0
			error(_): cancelled += 1

	expect_equal(cancelled, 50000)?

// Forty thousand task-backed reads at once used to exhaust the process's memory mappings
// (two per task stack); slots carved from large regions cost none.
test "forty thousand concurrent file reads complete":
	dir := temporary_directory("many-tasks")?
	path := dir + "/read.txt"
	write_file(path, "hello").wait()?

	var reads: List[Promise[Bytes]] = []
	for unused in 0..40000:
		reads.append(read_file(path, none))

	results := wait_all(reads)?
	var total = 0
	for data in results:
		total += data.length()
	expect_equal(total, 200000)?
	remove(dir, recursive: true)?
