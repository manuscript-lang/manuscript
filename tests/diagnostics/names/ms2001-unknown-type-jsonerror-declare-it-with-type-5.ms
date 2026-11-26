// conform: tags=diagnostics
// conform: phase=check
fn wrong(value Error) JsonError {
	return value
}
// expect-error: MS2001 3:23 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
