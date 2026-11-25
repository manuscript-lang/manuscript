// conform: tags=diagnostics
// conform: phase=check
fn copy[T](hold value T) &T => return value

export type Box[T] {
	value T
	copied T = copy(value)
	items List[T] = [value]
}
// expect-exit: 0
