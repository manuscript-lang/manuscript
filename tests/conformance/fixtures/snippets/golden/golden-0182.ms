// conform: tags=diagnostics
// conform: phase=check
fn identity[T](hold value T) &T {
	return value
}

fn call() Int {
	return identity(3)
}
