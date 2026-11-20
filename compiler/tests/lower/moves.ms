fn consume(move text: String) Int:
	return 1

fn pass(move text: String) String:
	return text

fn main() Int:
	a := "x" + "y"
	n := consume(a)
	b := "p" + "q"
	c := pass(b)
	d := consume(c)
	return n + d
