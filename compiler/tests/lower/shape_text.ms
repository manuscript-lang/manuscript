type Point:
	x: Int
	y: Int

fn show(p: Point) String:
	return f"<{p}>"

enum Shape:
	Dot
	Circle(radius: Float)
	Box(width: Int, solid: Bool)

type Mark:
	name: String
	at: Point
	kind: Shape

fn describe(s: Shape, m: Mark) String:
	return f"{s} and {m}"

fn main() Int:
	text := show(Point(x: 1, y: 2))
	box := Box(2, true)
	at := Point(x: 3, y: 4)
	mark := Mark(name: "", at: at, kind: Dot)
	both := describe(box, mark)
	return text.length() + both.length()
