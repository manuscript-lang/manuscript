// Enum and Optional matches the C body checker claims.
enum Shape:
	Circle(r: Float)
	Square(side: Float)
	Dot

fn area(s: Shape) Float:
	return match s:
		Circle(r): r * r * 3.0
		Square(side): side * side
		Dot: 0.0

fn qualified(s: Shape) Int:
	return match s:
		Shape.Circle(_): 1
		_: 2

fn or_zero(x: Int?) Int:
	return match x:
		v: v
		none: 0

fn label(x: Int?) String:
	return match x:
		v: "has"
		none: "none"

fn ignored(x: Int?) String:
	return match x:
		_v: "has"
		none: "none"

fn unused_payload(s: Shape) Int:
	return match s:
		Circle(r): 1
		_: 2
