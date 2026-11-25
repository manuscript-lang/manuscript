// conform: tags=diagnostics
// conform: phase=check
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
// expect-error: MS2001 3:11 unknown type Missing; declare it with 'type Missing:' / 'enum Missing:' / 'interface Missing:', declare it as a type parameter, or import it
