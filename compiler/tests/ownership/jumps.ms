fn continue_then_move(s: String, n: Int) String:
	x := s + "a"

	while n > 0:
		if n > 5: continue

		y := x
		return y

	return x

fn nested_continue(s: String, n: Int, m: Int) String:
	x := s + "a"

	while n > 0:
		while m > 0:
			if m > 5: continue

			y := x
			return y

		return "q"

	return x

fn break_then_use(s: String, n: Int) String:
	x := s + "a"

	while n > 0:
		if n > 2: break

		y := x
		_z := y + "k"

	return x

fn break_moves_after(s: String, n: Int) String:
	x := s + "a"

	while true:
		if n > 2: break

		b := x
		_c := b + "k"

	return x

fn loop_forever_returns(s: String) String:
	x := s + "a"
	while true:
		return x

fn borrow_across_continue(s: String, n: Int) String:
	x := s + "a"
	b := x

	while n > 0:
		if n > 1: continue

		c := x
		return c + b

	return b
