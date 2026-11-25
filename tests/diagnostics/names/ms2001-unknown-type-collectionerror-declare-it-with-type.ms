// conform: tags=diagnostics
// conform: phase=check
enum Other {
	OutOfRange
}

fn other() Other => Other.OutOfRange

fn standard() CollectionError => CollectionError.OutOfRange

fn recognize(value Other) Int {
	match value {
		OutOfRange => return 1
	}
}
// expect-error: MS2001 9:15 unknown type CollectionError; declare it with 'type CollectionError:' / 'enum CollectionError:' / 'interface CollectionError:', declare it as a type parameter, or import it
// expect-error: MS2001 9:34 unknown binding CollectionError; declare it with 'CollectionError := ...' before use, define 'fn CollectionError(...) T { ... }', or import it from a module
