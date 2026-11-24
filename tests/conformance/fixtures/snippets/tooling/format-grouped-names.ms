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
