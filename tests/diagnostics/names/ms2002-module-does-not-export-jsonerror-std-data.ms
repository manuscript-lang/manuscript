// conform: tags=diagnostics
// conform: phase=check
import (
	hex_decode from "@std/data/encoding.ms",
	JsonError from "@std/data/json.ms",
)

fn general(cause JsonError) Error {
	return cause
}

fn failed() Result[Void, JsonError] {
	return error(cause: JsonError.InvalidData)
}

fn forwarded() Result[Void, Error] {
	return failed()
}

fn propagated() Result[Void, Error] {
	bytes := hex_decode(text: "zz")?
	return ok(value: void)
}

fn constructed() Result[Void, Error] {
	return error(cause: JsonError.InvalidData)
}
// expect-error: MS2002 5:5-5:14 module does not export JsonError; @std/data/json.ms exports: JsonEncode, JsonOptions, JsonValue, StringifyOptions, json_reader, json_writer, parse, stringify; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/data/json.ms"'
// expect-error: MS2001 8:18 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
// expect-error: MS2001 12:26 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
// expect-error: MS2001 13:25 unknown binding JsonError; declare it with 'JsonError := ...' before use, define 'fn JsonError(...) T { ... }', or import it from a module
// expect-error: MS2001 26:25 unknown binding JsonError; declare it with 'JsonError := ...' before use, define 'fn JsonError(...) T { ... }', or import it from a module
