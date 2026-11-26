// conform: tags=alternatives,formatter,match,parser,records,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/control-flow/pattern-matching.md:59
enum Position {
	Point(x Int, y Int)
	Unknown
}

fn horizontal(position Position) Int {
	match position {
		Position.Point(horizontal_value, _) => {
			return horizontal_value
		}
		Position.Unknown => {
			return 0
		}
	}
}
// expect-format: rewritten
// expect-formatted: enum Position {
// expect-formatted: \tPoint(x, y Int)
// expect-formatted: \tUnknown
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn horizontal(position Position) Int {
// expect-formatted: \tmatch position {
// expect-formatted: \t\tPosition.Point(horizontal_value, _) => {
// expect-formatted: \t\t\treturn horizontal_value
// expect-formatted: \t\t}
// expect-formatted: \t\tPosition.Unknown => {
// expect-formatted: \t\t\treturn 0
// expect-formatted: \t\t}
// expect-formatted: \t}
// expect-formatted: }
