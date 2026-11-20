enum Shape:
	Circle(radius: Int)
	Square(side: Int)
	Empty

fn area(shape: Shape) Int:
	return match shape:
		Circle(r): r * r * 3
		Square(s): s * s
		Empty: 0

fn main() Int:
	return area(Square(4)) + area(Empty)
