// conform: tags=diagnostics
// conform: phase=check
fn wrong() Result[String, Error] {
	return Result[Int, JsonError].ok(value: 1)
}
// expect-error: MS2001 4:24 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
