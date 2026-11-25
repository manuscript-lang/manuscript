// conform: tags=diagnostics,formatter,match,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/pattern_positions_test.go:13 TestMatchPayloadPositionsSurviveRecovery
// café 🦀
fn use(value Envelope) Int {
	match value {
		Pair(_, NotFound) => return 1
	}
}
// expect-error: MS2001 5:14 unknown type Envelope; declare it with 'type Envelope:' / 'enum Envelope:' / 'interface Envelope:', declare it as a type parameter, or import it
