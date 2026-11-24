// conform: tags=testing,tier-core
// conform: phase=check
type T:
	n Int

fn T.f() Int:
	return 1

fn T.f() Int:
	return 2

fn main() Void:
	print(T(1).f())
