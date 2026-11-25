// conform: tags=diagnostics
// conform: phase=check
fn work(first Int, second String) Result[Map[String, String]?, ApplicationError] {
	return error(cause)
}
// expect-error: MS2001 3:64 unknown type ApplicationError; declare it with 'type ApplicationError:' / 'enum ApplicationError:' / 'interface ApplicationError:', declare it as a type parameter, or import it
// expect-error: MS2001 4:18 unknown binding cause; declare it with 'cause := ...' before use, define 'fn cause(...) T { ... }', or import it from a module
