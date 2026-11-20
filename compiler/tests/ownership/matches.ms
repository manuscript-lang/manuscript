enum Shape:
	Circle(radius: Int)
	Rect(width: Int, height: Int)
	Empty

fn literal_returned(n: Int) String:
	return match n:
		0: "zero"
		_: "many"

fn literal_bound(n: Int, s: String) String:
	label := match n:
		0: s + "a"
		1: s + "b"
		_: s

	return label

fn scrutinee_string(s: String) Bool:
	return match s:
		"yes": true
		_: false

fn scrutinee_owned(s: String) Bool:
	x := s + "a"

	return match x:
		"ya": true
		_: false

fn scrutinee_owned_used_again(s: String) String:
	x := s + "a"

	_ok := match x:
		"ya": 1
		_: 2

	return x + "b"

fn enum_payload(s: Shape) Int:
	return match s:
		Circle(r): r * r
		Rect(w, h): w * h
		Empty: 0

fn arm_body(s: Shape, n: Int) Int:
	return match s:
		Circle(r):
			twice := r + r
			twice + n
		_: n

fn arm_moves_one_side(s: String, n: Int) String:
	x := s + "a"

	return match n:
		0: x
		_: s

fn arm_moves_then_later_use(s: String, n: Int) String:
	x := s + "a"

	y := match n:
		0: x + "b"
		_: s

	return x + y

fn arm_borrow_ends(s: String, n: Int) String:
	x := s + "a"

	return match n:
		0:
			b := x
			b + "q"
		_: x

fn if_value(c: Bool, a: Int, b: Int) Int:
	return if c: a + 1 else: if a > b: a else: b
