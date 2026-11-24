// conform: tags=cancellation,scope-cleanup,tier-io
// conform: phase=run
import (
	PromiseOptions, promise from "@std/concurrency/promise.ms",
	connect, listen from "@std/net/net.ms",
	nanoseconds from "@std/time.ms",
)

fn read_one(address String) Int:
	var client = connect(address, timeout: nanoseconds(2000000000)).wait().get()
	got := client.input.next()

	match got:
		ok(chunk):
			if chunk != null: return chunk.length()
			return -1
		error(_): return -1

fn main() Void:
	server := listen("127.0.0.1:0").get()
	target := server.address().clone()
	work := promise(fn: ok(read_one(target.clone())))
	void work.with(options: PromiseOptions(timeout: nanoseconds(200000000))).wait()
	print("done")
