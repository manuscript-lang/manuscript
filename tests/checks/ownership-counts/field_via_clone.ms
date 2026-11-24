// expect-debug: allocs=22 alloc_bytes=1066
// expect-release: allocs=22 alloc_bytes=1066
// Reading a field through a function that returns an owned clone; field_via_ref.ms
// lends it. The floor for elision.
type Box:
	name String

fn name_of(b Box) String:
	return b.name.clone()

export fn main() Int:
	var total = 0

	for i in 0..20:
		b := Box(f"a name that is long enough to live on the heap {i}")
		total += name_of(b).length()

	return total - total
