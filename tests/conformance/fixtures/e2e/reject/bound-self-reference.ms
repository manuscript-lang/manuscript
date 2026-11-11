// conform: tags=testing,tier-core
// conform: phase=check
type Box[T: Box[T]]:
	value: T

export fn main() Int:
	return 0
