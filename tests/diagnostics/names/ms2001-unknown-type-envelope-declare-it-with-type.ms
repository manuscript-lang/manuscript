// conform: tags=diagnostics
// conform: phase=check
// café 🦀
fn use(value Envelope) Int {
	match value {
		Pair(_, NotFound) => return 1
	}
}
// expect-error: MS2001 4:14 unknown type Envelope; declare it with 'type Envelope:' / 'enum Envelope:' / 'interface Envelope:', declare it as a type parameter, or import it
