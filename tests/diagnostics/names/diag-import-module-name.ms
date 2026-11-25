// conform: tags=diagnostics,tier-core
// conform: phase=check
import json from "@std/data/json.ms"

export fn main() Int {
	return 0
}
// expect-error: MS2002 3:8-3:12 module does not export json; @std/data/json.ms is that module, and namespace imports are unsupported, so import what it exports by name: JsonEncode, JsonOptions, JsonValue, StringifyOptions, json_reader, json_writer, parse, stringify
