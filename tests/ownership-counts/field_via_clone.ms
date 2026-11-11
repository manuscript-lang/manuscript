// expect-debug: allocs=40 alloc_bytes=1980 expect-release: allocs=20 alloc_bytes=990
// Reading a field through a function that returns an owned clone; field_via_ref.ms
// lends it. The floor for elision.
type Box:
	name: String

fn name_of(b: Box) String:
	return b.name.clone()

export fn main() Int:
	var total = 0

	for i in 0..20:
		b := Box("a name that is long enough to live on the heap {i}")
		total += name_of(b).length()

	return total - total
