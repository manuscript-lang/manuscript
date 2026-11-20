fn param_returned(s: String) String:
	return s

fn param_borrowed_then_returned(s: String) String:
	a := s
	t := a + "x"
	return t + s

fn borrow_of_borrow(s: String) String:
	a := s
	b := a
	return b + a

fn borrow_returned(s: String) String:
	a := s
	n := a + "x"
	return a

fn owned_moved_while_borrowed(s: String) String:
	x := s + "y"
	b := x
	c := x
	return b + c

fn owned_returned_while_borrowed(s: String) String:
	x := s + "y"
	b := x
	n := b + "z"
	return x

fn borrow_of_local_returned(s: String) String:
	x := s + "y"
	b := x
	n := x + "z"
	return b + n

fn moved_at_last_use() String:
	x := "x" + "y"
	b := x
	return b

fn moved_not_last_use() String:
	x := "x" + "y"
	var a = x
	n := x + a
	return n

fn borrow_released_before_move(s: String) String:
	x := s + "y"
	b := x
	n := b + "z"
	c := x
	return c + n

fn text_reads(s: String) String:
	a := s
	return "${a} ${s} ${a}"

fn scalars(n: Int, m: Int) Int:
	a := n
	b := a
	c := a + b + m
	return c

fn owned_second_holder(s: String) String:
	x := s + "q"
	a := x
	b := x
	c := a + b
	return x + c

fn return_borrow_of_owned(s: String) String:
	x := s + "q"
	a := x
	return a
