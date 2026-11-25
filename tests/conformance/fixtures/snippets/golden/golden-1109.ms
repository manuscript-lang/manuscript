// conform: tags=diagnostics
// conform: phase=check
fn choose(value Choice) Int {
	match value {
		first => return 1
		second => return 2
		third => {
			result := calculate()
			return result
		}
		_ => return 0
	}

	return 3
}
// expect-error: MS2001 3:17 unknown type Choice; declare it with 'type Choice:' / 'enum Choice:' / 'interface Choice:', declare it as a type parameter, or import it
