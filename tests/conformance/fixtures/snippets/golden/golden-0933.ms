// conform: tags=diagnostics
// conform: phase=check
interface Read {
	fn get[T]() T
}
// expect-exit: 0
