// expect-debug: allocs=26 alloc_bytes=2026
// expect-release: allocs=26 alloc_bytes=2026
// Reading list elements through `get` and cloning each; get_via_ref.ms lends them. The
// floor for elision.
fn total(names: List[String]) Int:
	var n = 0

	for i in 0..names.length():
		s := names.get(i).clone()
		n += s.length()

	return n

export fn main() Int:
	var names = List[String]()
	for i in 0..20:
		names.append(f"a name that is long enough to live on the heap {i}")
	return total(names) - total(names)
