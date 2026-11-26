// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/format/format_test.go:136 TestFormatCommentsAndErrors
// leading
fn sum(left Int, right Int) Int {  // sum
	return left + right  // trailing
}
// expect-format: rewritten
// expect-formatted: // leading
// expect-formatted: fn sum(left, right Int) Int {  // sum
// expect-formatted: \treturn left + right  // trailing
// expect-formatted: }
