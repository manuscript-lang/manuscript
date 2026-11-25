// conform: tags=optional,tier-core
// conform: phase=check
// conform: origin=design/wiki/compiler/compiler-change-checklist.md
fn bump(xs List[Int]?) Int {
	if xs == null { return 0 }
	return xs.map(x => x + 1).length()
}

export fn main() Int {
	return bump([1, 2])
}
// expect-exit: 0
