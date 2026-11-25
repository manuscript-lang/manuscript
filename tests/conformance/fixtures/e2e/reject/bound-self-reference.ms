// conform: tags=testing,tier-core
// conform: phase=check
type Box[T Box[T]] {
	value T
}

export fn main() Int {
	return 0
}
// expect-error: MS3000 3:12 a bound must be an interface; write T: SomeInterface where SomeInterface is declared with 'interface'
