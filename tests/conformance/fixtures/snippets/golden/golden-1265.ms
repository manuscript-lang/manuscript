// conform: tags=diagnostics
// conform: phase=check
fn read(values: List[Int]) Int:
	first := values.first()
	if first != null: return first + 1

	return 0
