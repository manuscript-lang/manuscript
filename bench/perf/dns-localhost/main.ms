import monotonic from "@std/time.ms"
import lookup from "@std/net/net.ms"
fn main() Unit:
	t0 := monotonic().tick
	var n = 0
	for i in 0..20000:
		n += lookup("localhost").get().length()
	t1 := monotonic().tick
	print("lookup {(t1 - t0) / 20000} ns/call {n}")
