import connect, listen from "@std/net/net.ms"
import promise from "@std/concurrency/promise.ms"
import seconds from "@std/time.ms"

fn accept_one(listener: Listener) Int:
	got := listener.accept(seconds(5)).wait()
	if got.is_ok():
		return 1
	return 0

fn main() Void!:
	listener := listen("127.0.0.1:0")?
	address := listener.address()
	work := promise(fn: ok(accept_one(listener)))
	client := connect(address, timeout: seconds(5)).wait()?
	print(f"connected")
	print(f"accepted {work.wait()?}")
	client.close()?
