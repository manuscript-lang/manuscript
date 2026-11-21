// expect-debug: allocs=15 alloc_bytes=80360 list_copies=3 list_copy_bytes=24008
// expect-release: allocs=3 alloc_bytes=32000 list_copies=0 list_copy_bytes=0
// Clones of dead lists and a map over a dead list: Release already moves them, Debug
// keeps three list copies (traced with gdb on ms_list_clone): the `xs.clone()` in `sorted_copy`
// (its parameter is borrowed), the runtime's clone inside `msrt_list_sorted` for `out.sort()`
// (Release runs the sort inline, so it has none), and the `xs.clone()` of `rebuild`, inlined into
// `main`, whose source dies right after it (Release moves it, Debug runs no last-use pass in a
// short function). The old Debug count of 1 was the sort alone: Cranelift copied the two MIR
// clones inline and did not count them; the C back end counts every clone. The optimized Debug
// MIR was byte-identical to the Rust optimizer's for this program, so no pass regressed.
// Reuse of consumed buffers must not raise either.
fn fill(n: Int) List[Int]:
	var xs = List[Int]()
	for i in 0..n:
		xs.append(i)
	return xs

fn doubled(xs: List[Int]) List[Int]:
	return xs.map(fn x: x * 2)

fn sorted_copy(xs: List[Int]) List[Int]:
	var out = xs.clone()
	out.sort()
	return out

fn rebuild(var xs: List[Int]) List[Int]:
	xs.append(1)
	return xs.clone()

export fn main() Int:
	a := fill(1000)
	b := doubled(a)
	c := sorted_copy(b)
	var d = c.clone()
	e := rebuild(d)
	return e.length() - 1001
