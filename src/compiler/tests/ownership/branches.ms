fn moved_in_one_branch(s: String, flag: Bool) String:
	x := s + "a"
	if flag: return x

	return x + "b"

fn moved_then_used(s: String, flag: Bool) String:
	x := s + "a"

	if flag:
		y := x
		return y

	n := x + "c"
	return n

fn borrow_in_branch_ends(s: String, flag: Bool) String:
	x := s + "a"

	if flag:
		b := x
		n := b + "z"
		return n
	else:
		return x

fn borrow_outlives_branch(s: String, flag: Bool) String:
	x := s + "a"
	b := x

	if flag:
		c := b
		return c + b

	return x + b

fn move_while_branch_borrow(s: String, flag: Bool) String:
	x := s + "a"

	if flag:
		b := x
		c := x
		return b + c

	return x

fn loop_uses_again(s: String, n: Int) String:
	x := s + "a"
	while n > 0:
		t := x + "b"
	return x

fn loop_moves(s: String, n: Int) String:
	x := s + "a"

	while n > 0:
		y := x
		return y

	return x

fn loop_borrow(s: String, n: Int) String:
	x := s + "a"
	b := x

	while n > 0:
		t := b + "c"
		return t

	return x + b

fn nested(s: String, n: Int, flag: Bool) String:
	x := s + "a"

	while n > 0:
		if flag:
			y := x
			return y

		z := x + "q"
		return z

	return x

fn loop_move_each_pass(s: String, n: Int) String:
	x := s + "a"
	b := x

	while n > 0:
		y := x
		z := y + b

	return b

fn loop_borrow_released(s: String, n: Int) String:
	x := s + "a"

	while n > 0:
		b := x
		z := b + "k"

	return x

fn if_else_both_move(s: String, flag: Bool) String:
	x := s + "a"

	if flag:
		y := x
		return y
	else:
		z := x
		return z

fn mixed_returns_branches(s: String, flag: Bool) String:
	x := s + "a"
	if flag: return s

	return x
