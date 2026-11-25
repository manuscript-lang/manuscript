// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
	xs := [1, 2, 3]
	if xs.some(fn(x Int) Bool => x > 2) { return 1 }

	return 0
}
// expect-error: MS2001 5:11 unknown or ambiguous member some on List[Int]; some(predicate) is now any(predicate)
