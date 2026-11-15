type Point:
	x: Int
	y: Float
	name: String

enum Shape:
	Circle(r: Float)
	Rect(w: Int, h: Int)
	Empty

fn describe(s: Shape, p: Point, items: List[String], maybe: Int?, depth: Int) Int:
	if depth > 0: return describe(s, p, items, maybe, depth - 1)
	return items.length() + p.x

fn main() Unit:
	p := Point(1, 2.0, "pt")
	print(describe(Shape.Rect(2, 3), p, ["a", "b"], 5, 1))
