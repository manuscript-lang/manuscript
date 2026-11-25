// conform: tags=diagnostics,formatter,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/checker/json_parse_test.go:18 TestParseTypeArgument
fn f(text String) JsonValue! {
	return parse(text)
}
// expect-error: MS2001 4:19 unknown type JsonValue; add: import JsonValue from "@std/data/json.ms"
// expect-fix: 1:1-1:1 "import JsonValue from \"@std/data/json.ms\"\n"
// expect-error: MS2001 5:12 unknown binding parse; add: import parse from "@std/data/csv.ms"
// expect-fix: 1:1-1:1 "import parse from \"@std/data/csv.ms\"\n"
