// conform: tags=diagnostics,generics,strings,tier-core,try-result
// conform: phase=check
// conform: origin=pkg/checker/json_parse_test.go:23 TestParseTypeArgument
fn f[T](text String) T! {
	return parse[T](text)
}
// expect-error: MS2001 5:12 unknown binding parse; add: import parse from "@std/data/csv.ms"
// expect-fix: 1:1-1:1 "import parse from \"@std/data/csv.ms\"\n"
