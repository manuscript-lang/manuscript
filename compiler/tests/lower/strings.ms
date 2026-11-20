fn greet(name: String) String:
	text := "hello " + name
	return text

fn pair(a: String, b: String) String:
	joined := a + b
	more := joined + a
	return more

fn label(n: Int) String:
	s := "n"

	if n > 0:
		t := s + s
		return t

	return s

fn main() Int:
	g := greet("x")
	p := pair(g, "y")
	greet(p)
	label(1)
	return 0
