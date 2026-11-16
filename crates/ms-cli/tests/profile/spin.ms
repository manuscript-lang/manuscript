import arguments from "@std/os/env.ms"

fn work(n: Int) Int:
	var total = 0
	for i in 0..n:
		total += i % 7
	return total

// Burns enough CPU for the sampler to see `work`, echoes its arguments and exits with status 3.
fn main() Int:
	print(f"hello {arguments().join(" ")} {work(100000000)}")
	return 3
