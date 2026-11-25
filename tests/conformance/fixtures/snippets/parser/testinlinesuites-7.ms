// conform: tags=control-flow,diagnostics,tier-core,scope-cleanup
// conform: phase=check
// conform: origin=pkg/parser/parser_test.go:204 TestInlineSuites
fn f() Void {
	while true { break }
	for x in values { consume(x) }
}
// expect-error: MS2001 6:14 unknown binding values; add: import values from "@std/bytes.ms"
// expect-fix: 1:1-1:1 "import values from \"@std/bytes.ms\"\n"
// expect-error: MS2001 6:23 unknown binding consume; declare it with 'consume := ...' before use, define 'fn consume(...) T { ... }', or import it from a module
