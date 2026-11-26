// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/documentation_test.go:179 TestModuleDocumentationCapturesLeadingComments
// Adds two numbers.
// Never rounds.
export fn add(a Int, b Int) Int {
	return a + b
}

// Detached by a blank line.
export fn sub(a Int, b Int) Int {
	return a - b
}

// Not a doc comment: private declaration.
fn helper() Int {
	return 1
}

export fn bare() Int {
	return 0
}
// expect-format: rewritten
// expect-formatted: // Adds two numbers.
// expect-formatted: // Never rounds.
// expect-formatted: export fn add(a, b Int) Int {
// expect-formatted: \treturn a + b
// expect-formatted: }
// expect-formatted:
// expect-formatted: // Detached by a blank line.
// expect-formatted: export fn sub(a, b Int) Int {
// expect-formatted: \treturn a - b
// expect-formatted: }
// expect-formatted:
// expect-formatted: // Not a doc comment: private declaration.
// expect-formatted: fn helper() Int {
// expect-formatted: \treturn 1
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn bare() Int {
// expect-formatted: \treturn 0
// expect-formatted: }
