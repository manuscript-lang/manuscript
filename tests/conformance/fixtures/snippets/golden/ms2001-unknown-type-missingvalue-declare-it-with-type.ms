// conform: tags=diagnostics
// conform: phase=check
fn first(values List[Int]) Result[Int, MissingValue] => ok_or(
	values.first(),
	Error("missing"),
)

fn message(values List[Int]) String => first(values).err().message()

fn widen(cause MissingValue) Error => cause
// expect-error: MS2001 3:40 unknown type MissingValue; declare it with 'type MissingValue:' / 'enum MissingValue:' / 'interface MissingValue:', declare it as a type parameter, or import it
// expect-error: MS2001 10:16 unknown type MissingValue; declare it with 'type MissingValue:' / 'enum MissingValue:' / 'interface MissingValue:', declare it as a type parameter, or import it
