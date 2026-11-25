// conform: tags=diagnostics
// conform: phase=check
fn f(text String) Result[JsonValue, JsonError] {
	return parse(text)
}
// expect-error: MS2001 3:26 unknown type JsonValue; add: import JsonValue from "@std/data/json.ms"
// expect-fix: 1:1-1:1 "import JsonValue from \"@std/data/json.ms\"\n"
// expect-error: MS2001 3:37 unknown type JsonError; declare it with 'type JsonError:' / 'enum JsonError:' / 'interface JsonError:', declare it as a type parameter, or import it
// expect-error: MS2001 4:12 unknown binding parse; add: import parse from "@std/data/csv.ms"
// expect-fix: 1:1-1:1 "import parse from \"@std/data/csv.ms\"\n"
