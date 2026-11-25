// conform: tags=diagnostics
// conform: phase=check
fn use(value Int?) Int {
	n := value
	if n != null { return n }

	return 0
}
