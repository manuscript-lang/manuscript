// conform: tags=testing,tier-core
// conform: phase=check
type T {
	n Int
}

fn T.f() Int {
	return 1
}

fn T.f() Int {
	return 2
}

fn main() Void {
	print(T(1).f())
}
// expect-error: MS3000 11:6 duplicate operation f; rename or remove one of them
// expect-error: MS2001 16:16 ambiguous member f on T; more than one method provides it
