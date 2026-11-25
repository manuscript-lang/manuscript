// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=internal/cli/cli_test.go:449 TestFormatDropLabelsOnlyForCheckedSource
fn add(left Int, right Int) Int => left + right

fn total(left Int, right Int) Int {
	return add(left: left, right: right)
}
// expect-format: rewritten
// expect-formatted: fn add(left, right Int) Int => left + right
// expect-formatted:
// expect-formatted: fn total(left, right Int) Int {
// expect-formatted: \treturn add(left: left, right: right)
// expect-formatted: }
