type Point:
	x: Int
	y: Int

fn Point.to_string() String:
	return "p"

fn show(p: Point, n: Int) String:
	return f"{p}-{n}"

fn main() Int:
	text := show(Point(x: 1, y: 2), 3)
	if text.length() > 100:
		return 1
	return 0
