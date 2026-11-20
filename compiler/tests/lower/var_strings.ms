fn build(n: Int) String:
	var out = "head"

	for i in 0..n:
		if i == 3: break

		out += "x"

	return out

fn pick(n: Int) String:
	var s = "a"

	if n > 2:
		s = "big"
	else:
		s += "!"

	return s

fn early(n: Int) String:
	var s = "one"
	var t = "two"

	for i in 0..n:
		var u = s + t
		if i == 1: return u
		if i == 2: continue

		t = u

	return t

fn size(n: Int) Int:
	var s = "ab"

	while n > 0:
		s += "c"
		if n == 5: return 1

		return 2

	return 3

fn main() Int:
	if build(5) == "headxxx": return 0
	return 1
