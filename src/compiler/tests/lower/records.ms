type Point:
	x: Int
	y: Int

type Sized:
	width: Float
	live: Bool

fn sum(p: Point) Int:
	return p.x + p.y

fn make(a: Int, b: Int) Point:
	return Point(x: a, y: b)

fn area(s: Sized) Float:
	if s.live: return s.width * s.width
	return 0.0

fn main() Int:
	p := make(1, 2)
	q := Point(x: 3, y: 4)
	n := area(Sized(width: 2.0, live: true))
	if n > 3.0: return sum(p) + sum(q)

	return 0
