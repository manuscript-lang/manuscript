// conform: tags=diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/html_unescape_test.go:12 TestHTMLUnescapeRejectsInvalidContracts
fn wrong() String {
	convert := unescape
	return convert(value: "&amp;")
}
// expect-error: MS2001 5:16 unknown binding unescape; add: import unescape from "@std/data/html.ms"
// expect-fix: 1:1-1:1 "import unescape from \"@std/data/html.ms\"\n"
