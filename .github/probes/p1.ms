import (
	SpawnOptions, Stdio, spawn from "@std/os/process.ms",
)

fn main() Void:
	started := spawn("EXE", ["a"], SpawnOptions(stdin: Stdio.Inherit, stderr: Stdio.Inherit))
	if started.is_error():
		print("probe 1: spawn failed")
		return

	var child = started.get()
	var out = child.stdout()
	var n = 0
	while true:
		chunk := out.next()
		if chunk.is_error(): break
		if chunk.get().is_none(): break

		n += 1

	print(f"probe 1: chunks {n} waited {child.wait().is_ok()}")
