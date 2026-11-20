fn replace_owned(s: String) String:
	var x = s + "a"
	x = s + "b"
	return x

fn read_then_replace(s: String) String:
	var x = s + "a"
	n := x + "c"
	x = n
	return x

fn grow(s: String) String:
	var x = s + "a"
	x += "b"
	return x

fn replace_while_borrowed(s: String) String:
	var x = s + "a"
	b := x
	x = s + "b"
	return b + x

fn replace_after_borrow_ends(s: String) String:
	var x = s + "a"
	b := x
	n := b + "z"
	x = n
	return x

fn assign_in_loop(s: String, n: Int) String:
	var x = s + "a"

	while n > 0:
		x += "b"
		if n > 3: break

	return x

fn move_into_assignment(s: String) String:
	var x = s + "a"
	y := s + "b"
	x = y
	return x

fn counter(n: Int) Int:
	var i = 0
	while i < n:
		i += 1
	return i

fn replace_borrowed_origin(s: String) String:
	var x = s + "a"
	b := x
	n := x + "q"
	x = s + "b"
	return b + n
