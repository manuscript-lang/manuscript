type Point:
	x: Int
	y: Int

type Named:
	name: String
	at: Point

enum Shape:
	Dot
	Circle(radius: Int)
	Pair(a: Int, b: Bool)

fn same_point(a: Point, b: Point) Bool:
	return a == b

fn other_point(a: Point, b: Point) Bool:
	return a != b

fn same_named(a: Named, b: Named) Bool:
	return a == b

fn same_shape(a: Shape, b: Shape) Bool:
	return a == b

fn same_list(a: List[Int], b: List[Int]) Bool:
	return a == b

fn same_texts(a: List[String], b: List[String]) Bool:
	return a == b

fn same_maybe(a: Int?, b: Int?) Bool:
	return a == b

fn main() Int:
	p := Point(1, 2)
	n := Named("a", Point(3, 4))
	xs := [1, 2]
	ys := [1, 2]
	ts := ["a"]
	us := ["b"]
	if same_point(p, p) and not other_point(p, p) and same_named(n, n):
		return 1
	if same_shape(Circle(3), Circle(3)) or same_shape(Dot, Pair(1, true)):
		return 2
	if same_list(xs, ys) or same_texts(ts, us) or same_maybe(1, none):
		return 3
	return 0
