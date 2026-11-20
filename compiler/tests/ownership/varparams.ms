fn bump(var count: Int, by: Int) Void:
	count += by

fn twice(var count: Int) Void:
	bump(count, 1)
	bump(count, 2)

fn counted() Int:
	var total = 0
	bump(total, 3)
	twice(total)
	return total

fn not_a_var() Int:
	total := 0
	bump(total, 1)
	return total

fn plain_param(n: Int) Int:
	bump(n, 1)
	return n

fn computed() Int:
	var total = 0
	bump(total + 1, 1)
	return total

fn append(var text: String, tail: String) Void:
	text += tail

fn joined(a: String) String:
	var out = a
	append(out, "x")
	append(out, "y")
	return out

fn give_up(var text: String) String:
	return text

fn keep(move text: String) String:
	return text

fn handed(s: String) String:
	t := keep(s)
	return t + s

fn handed_once(s: String) String:
	return keep(s)

fn consumes(s: String) String:
	t := s
	return t

fn consumer_caller(s: String) String:
	t := consumes(s)
	return t + s

fn consumer_last(s: String) String:
	return consumes(s)

fn same_twice() Void:
	var n = 1
	bump(n, n)

fn overlap(a: String) String:
	var out = a
	append(out, out)
	return out

fn moved_out(var text: String) String:
	t := text
	return t

fn consumed_twice(s: String) String:
	return keep(s) + keep(s)

fn changed_while_borrowed(a: String) String:
	var out = a
	b := out
	append(out, "x")
	return b
