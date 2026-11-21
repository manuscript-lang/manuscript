// Imports of project modules resolve through the graph: a type and a function of
// another module, and an imported constant.
import (
	LIMIT, double from "./lib.ms",
	Point, origin from "./shapes.ms",
)

fn start() Point:
	return origin()

fn shifted(p: Point) Int:
	return double(p.x)

fn capped(n: Int) Int:
	return n + LIMIT
