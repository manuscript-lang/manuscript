// conform: tags=diagnostics
// conform: phase=check
fn wrong(operation fn() JsonError) fn() Error {
	return operation
}
// expect-error: MS2001 3:25 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
