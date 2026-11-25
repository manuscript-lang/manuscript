// conform: tags=diagnostics
// conform: phase=check
import hex_decode from "@std/data/encoding.ms"

fn wrong() Result[Void, JsonError] {
	bytes := hex_decode(text: "ff", max_bytes: 1)?
	return ok(value: void)
}
// expect-error: MS2001 5:25 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
