type Point:
	x: Int
	y: Int

fn norm(p: Point) Int:
	return p.x + p.y

fn shifted(p: Point, by: Int = 1) Int:
	return p.x + by

fn main() Int:
	p := Point(1, 2)
	return norm(p) + shifted(p) + shifted(p, 3)
