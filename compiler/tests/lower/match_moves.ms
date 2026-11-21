enum Msg:
	Text(body: String, id: Int)
	Quit

fn make(s: String, n: Int) Msg:
	return Text(s, n)

fn named(s: String) Int:
	m := make(s, 1)

	return match m:
		Text(body, _): body.length()
		Quit: 0

fn handed(s: String) String:
	return match make(s, 1):
		Text(body, _): body
		Quit: "none"

fn handed_local(s: String) String:
	m := make(s, 2)

	return match m:
		Text(body, _): body
		Quit: "q"

fn pass(n: String) String:
	return n

fn word(s: String) Int:
	t := s + "x"

	return match t:
		"ax": 1
		_: 0

fn main() Int:
	return named("a") + handed("b").length() + handed_local("c").length() + word("a")
