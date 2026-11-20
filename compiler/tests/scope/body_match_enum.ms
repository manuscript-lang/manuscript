// Case matches over an enum the module declares, as the C body checker claims them.
enum Shape:
	Circle(radius: Int)
	Rect(width: Int, height: Int)
	Empty

enum Color:
	Red
	Green
	Blue

fn area(s: Shape) Int:
	return match s:
		Circle(r): r * r * 3
		Rect(w, h): w * h
		Empty: 0

fn corner(s: Shape) Int:
	return match s:
		Shape.Rect(w, _): w
		_: 0

fn warm(c: Color) Bool:
	return match c:
		Red: true
		Green: false
		Blue: false

fn code(c: Color) Int:
	return match c:
		Red: 1
		_: 2

fn same(s: Shape, n: Int) Int:
	return match s:
		Circle(r):
			twice := r + r
			twice + n
		_: n

fn describe_arms(shape: Shape) Int:
	var total = 0

	match shape:
		Circle(r):
			total += r
		Rect(w, h):
			total += w * h
		Empty:
			total += 1

	return total
