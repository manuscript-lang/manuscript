fn same(s: String) String:
	return s

fn pick(a: String, b: String, flag: Bool) String:
	if flag: return a
	return b

fn build(s: String) String:
	return s + "!"

fn length_of(s: String) Int:
	return 3

fn double(n: Int) Int:
	return n + n

fn copy_args(n: Int) Int:
	return double(double(n))

fn owned_call_result(s: String) String:
	x := build(s)
	y := x
	return y

fn borrowed_result_bound(s: String) String:
	b := same(s)
	n := b + "q"
	return build(s) + n

fn kept_borrow_moved(s: String) String:
	b := same(s)
	c := s
	return b + c

fn borrowed_result_released(s: String) String:
	b := same(s)
	n := b + "z"
	c := s
	return c + n

fn temporary_source(s: String) String:
	b := same(s + "a")
	return b + s

fn call_as_condition(s: String) String:
	if length_of(s) > 2: return build(s)
	return build(s + "x")

fn call_statement(s: String) Int:
	length_of(s)
	return 1

fn recursive(n: Int) Int:
	if n > 0: return recursive(n - 1)
	return 0

fn two_sources(a: String, b: String) String:
	x := pick(a, b, true)
	n := x + "k"
	return n + a

fn nested_borrow(s: String) String:
	x := same(same(s))
	n := x + "k"
	return n + s

fn loop_calls(s: String, n: Int) String:
	x := s + "a"

	while n > 0:
		y := same(x)
		_z := y + "k"

	return x
