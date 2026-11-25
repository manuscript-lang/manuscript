// conform: tags=diagnostics
// conform: phase=check
interface Read {
	fn read(limit Int? = null) Int
}
// expect-exit: 0
