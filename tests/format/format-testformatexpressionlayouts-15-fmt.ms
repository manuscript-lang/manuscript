// conform: tags=closures,control-flow,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/format/format_layout_test.go:142 TestFormatExpressionLayouts
fn work() Int {
	value := (
		[2, 5, 3, (-6), (-9), 1, 2, 3, 4]
		.clone()
		.sorted(fn(l Int, r Int) Int => (l - r))
		.first()
	)
	if value != null {
		return value
	}

	return 0
}
// expect-format: rewritten
// expect-formatted: fn work() Int {
// expect-formatted: \tvalue := (
// expect-formatted: \t\t[2, 5, 3, (-6), (-9), 1, 2, 3, 4]
// expect-formatted: \t\t.clone()
// expect-formatted: \t\t.sorted(fn(l, r Int) Int => (l - r))
// expect-formatted: \t\t.first()
// expect-formatted: \t)
// expect-formatted: \tif value != null {
// expect-formatted: \t\treturn value
// expect-formatted: \t}
// expect-formatted:
// expect-formatted: \treturn 0
// expect-formatted: }
