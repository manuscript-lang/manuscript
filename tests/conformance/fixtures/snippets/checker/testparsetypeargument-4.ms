// conform: tags=diagnostics,formatter,records,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/checker/json_parse_test.go:21 TestParseTypeArgument
type Request {
	model String
}

fn f(text String) Request! {
	request := parse[Request](text)?
	return ok(request)
}
// expect-error: MS2001 9:16 unknown binding parse; add: import parse from "@std/data/csv.ms"
// expect-fix: 1:1-1:1 "import parse from \"@std/data/csv.ms\"\n"
