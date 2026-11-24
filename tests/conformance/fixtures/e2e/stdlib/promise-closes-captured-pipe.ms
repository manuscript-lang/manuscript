// conform: tags=closures,scope-cleanup,tier-io
// conform: phase=run
// conform: timeout=30
// A promise that captures a moved pipe closes its reader when the promise ends.
import (
	Promise, promise from "@std/concurrency/promise.ms",
	Pipe, pipe from "@std/io/io.ms",
)

fn drain(input Pipe[Int]) Void!:
	while true:
		item := input.receive()
		if item.is_error(): break

		raw := item.get()

		if raw != null:
			print(f"got {raw}")
		else:
			break

fn start(move input Pipe[Int]) Promise[Void]:
	return promise(fn: drain(input))

export fn main() Int:
	queue := pipe[Int](4)
	var writer = queue.writer()
	task := start(queue)
	void writer.write(7)
	void writer.close()
	void task.wait()
	return 0
