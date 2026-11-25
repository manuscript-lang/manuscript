// conform: tags=diagnostics
// conform: phase=check
enum Other {
	Missing(value Int)
}

fn other() Other => Other.Missing(1)

fn standard() MissingValue => MissingValue.Missing("location")

fn read(value Other) Int {
	match value {
		Missing(found) => return found
	}
}
// expect-error: MS2001 9:15 unknown type MissingValue; declare it with 'type MissingValue:' / 'enum MissingValue:' / 'interface MissingValue:', declare it as a type parameter, or import it
// expect-error: MS2001 9:31 unknown binding MissingValue; declare it with 'MissingValue := ...' before use, define 'fn MissingValue(...) T { ... }', or import it from a module
