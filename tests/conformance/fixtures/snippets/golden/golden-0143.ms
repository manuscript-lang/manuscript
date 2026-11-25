// conform: tags=diagnostics
// conform: phase=check
fn wrong() JsonError {
	return JsonError.PermissionDenied
}
// expect-error: MS2001 3:12 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
// expect-error: MS2001 4:12 unknown binding JsonError; declare it with 'JsonError := ...' before use, define 'fn JsonError(...) T { ... }', or import it from a module
