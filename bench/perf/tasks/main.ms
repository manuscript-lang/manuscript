// Memory and time per parked task: starts N promise tasks that park (mode `sleep`, on a
// timer;
// `deep`, on a timer after a 256-frame call chain, as a handler parks after real work; or
// `read`, after a file read), then reports the process's resident set and page tables.
// `ms run bench/perf/tasks/main.ms -- 1000000 sleep`. Linux only for the report
// (it reads /proc/self/status); the tasks themselves are portable.
import (
	Promise, owned_task from "@std/concurrency/promise.ms",
	arguments from "@std/os/env.ms",
	read_file from "@std/os/fs.ms",
	monotonic, seconds, sleep from "@std/time.ms",
)

fn status(label: String) Unit:
	text := read_file("/proc/self/status", none).wait().get().decode_utf8().get()
	for line in text.lines():
		if line.contains("VmRSS") or line.contains("VmHWM") or line.contains("VmPTE"):
			print(label + " " + line)

fn park_sleep(a: Int) Int!:
	try sleep(seconds(1000)).wait()
	return ok(a)

fn descend(depth: Int, acc: Int) Int:
	if depth == 0: return acc

	scratch: List[Int] := [acc, depth, acc + depth]
	below := descend(depth - 1, acc + scratch[1])
	return below + scratch.length()

fn park_deep(a: Int) Int!:
	sum := descend(256, a)
	try sleep(seconds(1000)).wait()
	return ok(sum)

fn park_read(a: Int) Int!:
	data := try read_file("/proc/self/stat", none).wait()
	try sleep(seconds(1000)).wait()
	return ok(data.length() + a)

fn main() Unit:
	args := arguments()
	n := args[0].parse_int().get()
	mode := args[1].clone()
	status("before")

	t0 := monotonic()
	var promises: List[Promise[Int]] = []

	for i in 0..n:
		if mode == "sleep":
			promises.append(owned_task[Int](fn: park_sleep(i)))
		else if mode == "deep":
			promises.append(owned_task[Int](fn: park_deep(i)))
		else:
			promises.append(owned_task[Int](fn: park_read(i)))

	t1 := monotonic()

	// Let every task start and park, then let the idle scheduler hibernate them.
	sleep(seconds(3)).wait().get()
	status("parked")
	sleep(seconds(3)).wait().get()
	status("idle")

	t2 := monotonic()
	print("spawn ms " + (t1.difference(t0).to_nanoseconds() / 1000000).to_string())
	for p in promises:
		p.cancel()

	t3 := monotonic()
	print("cancel ms " + (t3.difference(t2).to_nanoseconds() / 1000000).to_string())
