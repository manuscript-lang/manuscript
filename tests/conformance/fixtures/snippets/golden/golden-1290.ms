// conform: tags=diagnostics
// conform: phase=check
fn first(values List[Int]) Result[Int, MissingValue] => ok_or(
	values.first(),
	Error("missing"),
)
// expect-error: MS2001 3:40 unknown type MissingValue; declare it with 'type MissingValue:' / 'enum MissingValue:' / 'interface MissingValue:', declare it as a type parameter, or import it
