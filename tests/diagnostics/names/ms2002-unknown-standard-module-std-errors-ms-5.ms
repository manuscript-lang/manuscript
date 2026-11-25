// conform: tags=diagnostics
// conform: phase=check
import MissingValue from "@std/errors.ms"  // keep

fn first(
	values List[Int]
) Result[Int, MissingValue] => values.first().ok_or(Error("missing"))
// expect-error: MS2002 3:8-3:20 unknown standard module @std/errors.ms
// expect-error: MS2001 7:15 unknown type MissingValue; declare it with 'type MissingValue:' / 'enum MissingValue:' / 'interface MissingValue:', declare it as a type parameter, or import it
// expect-error: MS3000 7:47 a nullable has no method `ok_or`; write `ok_or(x, cause)`
// expect-fix: 7:32-7:70 "ok_or(values.first(), Error(\"missing\"))"
