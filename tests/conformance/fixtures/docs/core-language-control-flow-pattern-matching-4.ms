// conform: tags=diagnostics,formatter,match,tier-core
// conform: phase=check,parse
// conform: origin=documentation/core-language/control-flow/pattern-matching.md:83
fn paid(payment Payment) Bool {
	match payment {
		Paid(_) => {
			return true
		}
		_ => {
			return false
		}
	}
}
// expect-error: MS2001 4:17 unknown type Payment; declare it with 'type Payment:' / 'enum Payment:' / 'interface Payment:', declare it as a type parameter, or import it
