import (
	Bytes from "@std/bytes.ms",
	Promise, promise, wait_any from "@std/concurrency/promise.ms",
	ReadStream from "@std/io/io.ms",
	SpawnOptions, Stdio, spawn from "@std/os/process.ms",
	seconds, sleep from "@std/time.ms",
)

fn due() Int!:
	void sleep(seconds(30)).wait()
	return ok(1)

fn drain(var out: ReadStream[Bytes]) Int!:
	while true:
		chunk := out.next()?
		if chunk.is_none(): break

	return ok(0)

fn main() Void:
	started := spawn(
		"EXE",
		["a"],
		SpawnOptions(stdin: Stdio.Inherit, stderr: Stdio.Inherit),
	)
	if started.is_error(): return

	var child = started.get()
	var out = child.stdout()
	var pending = List[Promise[Int]]()
	pending.append(promise(fn: drain(out)))
	pending.append(promise(fn: due()))

	woke := wait_any(pending)
	print(f"probe 4: woke {woke.is_ok()}")
