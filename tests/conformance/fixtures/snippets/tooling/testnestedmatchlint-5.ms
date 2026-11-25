// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/nested_match_lint_test.go:24 TestNestedMatchLint
fn use(value Int?) Int {
	return match (
		match value {
			x => x
			null => 0
		}
	) {
		x => x
		null => 0
	}
}
// expect-error: MS3070 11:9 a match on Int takes literal arms such as 1, "text" or true, and a final '_ => ...' arm; to bind or compare computed values use if/else
// expect-error: MS3070 11:9 a literal arm has no payload to bind
// expect-error: MS3070 12:9 a match on Int takes literal arms such as 1, "text" or true, and a final '_ => ...' arm; to bind or compare computed values use if/else
// expect-error: MS3050 5:12 non-exhaustive match on Int; add a final '_ => ...' arm
// expect-error: MS2001 11:14 unknown binding x; declare it with 'x := ...' before use, define 'fn x(...) T { ... }', or import it from a module
