// expect-debug: allocs=2 alloc_bytes=48 expect-release: allocs=1 alloc_bytes=24 Today a
// field of an owned record leaves only by a deep copy. The partial-move stage should
// lower both counts.
type Big:
	name: String
	items: List[Int]

fn take(b: Big) List[Int]:
	return b.items.clone()

export fn main() Int:
	b := Big(name: "a name that is long enough to live on the heap", items: [1, 2, 3])
	xs := take(b)
	return xs.length() - 3
