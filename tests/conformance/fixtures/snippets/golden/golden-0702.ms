// conform: tags=diagnostics
// conform: phase=check

fn probe() Int {
	cell := Cell(0)
	var i = 0

	while i < 1000 {
		cell.bump(1)
		i += 1
	}

	return cell.total
}
// expect-error: MS2001 5:13 unknown binding Cell; declare it with 'Cell := ...' before use, define 'fn Cell(...) T { ... }', or import it from a module
