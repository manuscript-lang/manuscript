// conform: tags=closures,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/defaults_test.go:9 TestDefaultClosureAssignmentReferencesAndListHints
fn answer(
	value Int = (
		fn() Int {
			var current = 0
			current += 1
			return current
		}
	)()
) Int {
	callbacks := [
		fn() Int {
			nested := 1
			return nested
		}
	]
	return value + callbacks.length()
}
// expect-exit: 0
