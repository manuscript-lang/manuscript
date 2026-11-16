type Point:
	x: Int
	y: Float
	name: String

enum Shape:
	Circle(r: Float)
	Rect(w: Int, h: Int)
	Empty

fn describe(s: Shape, p: Point, items: List[String], depth: Int, maybe: Int?) Int:
	if depth > 0: return describe(s, p, items, depth - 1, maybe)
	return items.length() + p.x

fn main() Void:
	p := Point(1, 2.0, "pt")
	print(describe(Shape.Rect(2, 3), p, ["a", "b"], 1, 5))
