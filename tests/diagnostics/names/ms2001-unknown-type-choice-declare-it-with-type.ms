// conform: tags=diagnostics
// conform: phase=check
fn choose(value Choice) Int {
	match value {
		long_variant(
			first_payload_name,
			second_payload_name,
			third_payload_name,
			fourth_payload_name,
		) => return 1
		_ => return 0
	}
}
// expect-error: MS2001 3:17 unknown type Choice; declare it with 'type Choice:' / 'enum Choice:' / 'interface Choice:', declare it as a type parameter, or import it
