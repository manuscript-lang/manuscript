// conform: tags=diagnostics,records,strings,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/checker/json_parse_test.go:22 TestParseTypeArgument
type Request {
	model String
}

fn f(text String) Request! {
	request Request := parse(text)?
	return ok(request)
}
// expect-error: MS2001 9:24 unknown binding parse; add: import parse from "@std/data/csv.ms"
// expect-fix: 1:1-1:1 "import parse from \"@std/data/csv.ms\"\n"
