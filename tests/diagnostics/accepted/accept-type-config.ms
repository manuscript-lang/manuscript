// conform: tags=diagnostics
// conform: phase=check
type Config {
	value Result[Result[Int, Error], Error]
}
// expect-exit: 0
