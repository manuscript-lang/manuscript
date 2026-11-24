import (
	lookup from "@std/net/net.ms",
	monotonic from "@std/time.ms",
)

fn main() Void {
	t0 := monotonic().tick
	var n = 0
	for i in 0..20000 {
		n += lookup("localhost").get().length()
	}

	t1 := monotonic().tick
	print(f"lookup {(t1 - t0) / 20000} ns/call {n}")
}
