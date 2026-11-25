// expect-debug: allocs=8 alloc_bytes=2112
// expect-release: allocs=8 alloc_bytes=2112
// A `map`/`filter`/`sum` chain reads each stage's list once, so the stages run in one
// loop and only the source list is allocated (its growth by doubling): the count does
// not grow with the calls.
export fn main() Int {
	var xs = List[Int]()
	for i in 0..100 {
		xs.append(i)
	}

	var total = 0
	for r in 0..1000 {
		total += xs.map(x => x * r).filter(x => x % 3 == 0).sum()
	}
	return total - total
}
