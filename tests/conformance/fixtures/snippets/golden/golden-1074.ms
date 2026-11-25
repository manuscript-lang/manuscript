// conform: tags=diagnostics
// conform: phase=check
fn work() Int {
	var total = 1
	total += 2
	total *= 3
	box.count -= total
	return total
}
// expect-error: MS2001 7:5 unknown binding box; declare it with 'box := ...' before use, define 'fn box(...) T { ... }', or import it from a module
// expect-error: MS3000 7:9 assignment requires a type field; only fields of a type value can be assigned with 'x.field = ...'
