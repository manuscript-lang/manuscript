// conform: tags=diagnostics
// conform: phase=check
fn wrong() Result[Void, JsonError] {
	return error(cause: EncodingError.InvalidData)
}
// expect-error: MS2001 3:25 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
// expect-error: MS2001 4:25 unknown binding EncodingError; declare it with 'EncodingError := ...' before use, define 'fn EncodingError(...) T { ... }', or import it from a module
