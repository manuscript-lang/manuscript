// conform: tags=diagnostics,match,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/format/format_paragraphs_test.go:128 TestFormatParagraphs
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
// expect-error: MS2001 4:17 unknown type Choice; declare it with 'type Choice:' / 'enum Choice:' / 'interface Choice:', declare it as a type parameter, or import it
