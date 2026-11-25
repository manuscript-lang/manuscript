// conform: tags=diagnostics
// conform: phase=check
import JsonError from "@std/data/json.ms"

fn describe(cause Error) String {
	match cause {
		JsonError(json) => {
			return json.message()
		}
		_ => {
			return cause.message()
		}
	}
}
// expect-error: MS2002 3:8-3:17 module does not export JsonError; @std/data/json.ms exports: JsonEncode, JsonOptions, JsonValue, StringifyOptions, json_reader, json_writer, parse, stringify; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/data/json.ms"'
// expect-error: MS3000 6:5 match requires an alternative, contract view, Int, String or Bool, found Error; match on a type with cases, or use if/else
