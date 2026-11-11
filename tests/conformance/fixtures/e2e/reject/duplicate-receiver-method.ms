// conform: tags=testing,tier-core
// conform: phase=check
type T:
	n: Int

fn T.f() Int:
	return 1

fn T.f() Int:
	return 2

fn main() Unit:
	print(T(1).f())
