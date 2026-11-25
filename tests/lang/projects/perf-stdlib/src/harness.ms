import (
	stdout from "@std/io/io.ms",
	monotonic from "@std/time.ms",
)

// Shared helpers for the standard-library micro-benchmarks.
export type Point {
	x Int
	y Int
}

export fn say(text String) Void {
	_ignored := stdout().write(text.clone())
}

// Runs `body` once and prints `name<TAB>ops<TAB>ns_per_op`; `body` returns a checksum
// that keeps its work observable.
export fn bench(name String, ops Int, body fn() Int) Void {
	started := monotonic()
	checksum := body()
	elapsed := monotonic().difference(started).to_nanoseconds()
	say(f"{name}\t{ops}\t{elapsed / ops}\n")
	say(f"# checksum {name} {checksum}\n")
	say(f"# elapsed {name} {elapsed}\n")
}

export fn ints(count Int) List[Int] {
	var out List[Int] = []
	for i in 0..count {
		out.append((i * 7919) % 10007)
	}
	return out
}

export fn words(count Int) List[String] {
	var out List[String] = []
	for i in 0..count {
		out.append(f"word{i % 977}")
	}
	return out
}
