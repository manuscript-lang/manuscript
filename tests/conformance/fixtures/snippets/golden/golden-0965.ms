// conform: tags=diagnostics
// conform: phase=check
export fn later[T](hold value T) &T {
	return value
}
