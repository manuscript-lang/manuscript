// conform: tags=diagnostics
// conform: phase=check
export interface Read[T] {
	fn get() T
}
// expect-exit: 0
