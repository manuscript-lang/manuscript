// conform: tags=closures,formatter,parser,strings,tier-core
// conform: phase=parse
// conform: origin=pkg/checker/documentation_test.go:128 TestModuleDocumentationRetainsDefaults
fn helper(left Int, right Int) Int {
	return left + right
}

export fn defaults(
	first Int = -3,
	second Int = helper(left: first, right: 2),
	text String = "literal, )",
	callback fn(Int) Int = (
		fn(value Int) Int {
			return value + 1
		}
	)
) Int {
	return callback(second)
}
// expect-format: rewritten
// expect-formatted: fn helper(left, right Int) Int {
// expect-formatted: \treturn left + right
// expect-formatted: }
// expect-formatted:
// expect-formatted: export fn defaults(
// expect-formatted: \tfirst Int = -3,
// expect-formatted: \tsecond Int = helper(left: first, right: 2),
// expect-formatted: \ttext String = "literal, )",
// expect-formatted: \tcallback fn(Int) Int = (
// expect-formatted: \t\tfn(value Int) Int {
// expect-formatted: \t\t\treturn value + 1
// expect-formatted: \t\t}
// expect-formatted: \t)
// expect-formatted: ) Int {
// expect-formatted: \treturn callback(second)
// expect-formatted: }
