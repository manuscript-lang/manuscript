// conform: tags=testing,tier-core,closures
// conform: phase=check
// A returned closure that keeps a borrowed parameter would need a copy no `.clone()` asked
// for, so the checker rejects it: take the parameter with `move`, or capture a `.clone()`.
type Big {
	name String
	items List[Int]
}

fn size_reader(big Big) fn() Int {
	return () => big.items.length()
}

export fn main() Int {
	read := size_reader(Big("a name that is long enough to live on the heap", [1, 2]))
	return read()
}
// expect-error: MS3000 11:12 this closure outlives the statement but captures `big`, which is borrowed, not owned; bind `own := big.clone()` before the closure and capture `own` instead
