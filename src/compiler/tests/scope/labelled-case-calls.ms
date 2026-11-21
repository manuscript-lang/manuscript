enum Shape:
	Circle(radius: Int)
	Rect(width: Int, height: Int)

fn parse(n: Int) Result[Int, String]:
	if n < 0: return error(cause: "negative")
	return ok(value: n)

fn circle(n: Int) Shape:
	return Circle(radius: n)

fn rect(w: Int, h: Int) Shape:
	return Rect(width: w, height: h)

fn wrong(n: Int) Shape:
	return Circle(r: n)

fn main() Int:
	return 0
