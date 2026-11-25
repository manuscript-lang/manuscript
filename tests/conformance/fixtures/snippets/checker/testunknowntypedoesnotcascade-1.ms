// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/defaults_test.go:89 TestUnknownTypeDoesNotCascade
fn peek() Missing {
	return 0
}

fn f() Int {
	match peek() {
		x => {
			return x
		}
		null => {
			return 0
		}
	}
}
// expect-error: MS2001 4:11 unknown type Missing; declare it with 'type Missing:' / 'enum Missing:' / 'interface Missing:', declare it as a type parameter, or import it
