// expect-debug: allocs=6 alloc_bytes=226
// expect-release: allocs=6 alloc_bytes=226
// The caller's `p` is dead after the call, but `left_of` reads it borrowed, so its
// clone still allocates. Passing a dead argument by move to a function that only clones
// from it should lower both counts.
type Big {
	name String
	items List[Int]
}

type Pair {
	left, right Big
}

fn left_of(p Pair) Big {
	l := p.left.clone()
	return l
}

export fn main() Int {
	p := Pair(
		left: Big(
			name: "a name that is long enough to live on the heap",
			items: [1, 2, 3],
		),
		right: Big(
			name: "another name that is long enough to live on the heap",
			items: [4],
		),
	)
	l := left_of(p)
	return l.items.length() - 3
}
