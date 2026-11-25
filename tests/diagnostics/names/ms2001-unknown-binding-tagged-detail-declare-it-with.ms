// conform: tags=diagnostics
// conform: phase=check
fn work() Int {
	if tagged_detail(integer) != "integer 7" or tagged_detail(text) != "text diagnostic" {
		return 1
	}
	return 0
}
// expect-error: MS2001 4:8 unknown binding tagged_detail; declare it with 'tagged_detail := ...' before use, define 'fn tagged_detail(...) T { ... }', or import it from a module
// expect-error: MS2001 4:49 unknown binding tagged_detail; declare it with 'tagged_detail := ...' before use, define 'fn tagged_detail(...) T { ... }', or import it from a module
