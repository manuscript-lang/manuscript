// conform: tags=diagnostics
// conform: phase=check
fn wrong(values List[JsonError]) List[Error] {
	return values
}
// expect-error: MS2001 3:22 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
