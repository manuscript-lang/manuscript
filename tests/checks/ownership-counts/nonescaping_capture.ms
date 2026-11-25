// expect-debug: allocs=3 alloc_bytes=120
// expect-release: allocs=3 alloc_bytes=120
// A closure that captures a local and is only passed down to a call: Release
// specializes it away (no environment), Debug keeps one environment allocation. Stack
// environments must not raise either.
fn apply(xs List[Int], f fn(Int) Int) Int {
	var t = 0
	for x in xs {
		t += f(x)
	}
	return t
}

export fn main() Int {
	xs := [1, 2, 3]
	k := 5
	r := apply(xs, x => x + k)
	return r - 21
}
