// conform: tags=parser,tier-core
// conform: phase=parse
type Rect {
	width Int
	height Int
	label String = "r"
	x Float = 0.5
	y Float = 0.5
	// a comment keeps its neighbours apart
	left Int
	right Int
}

enum Shape {
	Box(width Int, height Int)
	Dot
}

fn area(width Int, height Int, scale Float, shift Float = 1.0) Int => width

fn apply(first Int, second Int, f fn(Int, Int) Int) Int => f(first, second)
// expect-format: rewritten
// expect-formatted: type Rect {
// expect-formatted: \twidth, height Int
// expect-formatted: \tlabel String = "r"
// expect-formatted: \tx, y Float = 0.5
// expect-formatted: \t// a comment keeps its neighbours apart
// expect-formatted: \tleft, right Int
// expect-formatted: }
// expect-formatted:
// expect-formatted: enum Shape {
// expect-formatted: \tBox(width, height Int)
// expect-formatted: \tDot
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn area(width, height Int, scale Float, shift Float = 1.0) Int => width
// expect-formatted:
// expect-formatted: fn apply(first, second Int, f fn(Int, Int) Int) Int => f(first, second)
