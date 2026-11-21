import (
	Bytes from "@std/bytes.ms",
	promise from "@std/concurrency/promise.ms",
	ReadStream from "@std/io/io.ms",
	SpawnOptions, Stdio, spawn from "@std/os/process.ms",
)

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
	done := promise(fn: drain(out)).wait()
	print(f"probe 5: promise drain {done.is_ok()}")
