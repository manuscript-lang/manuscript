enum Msg:
	Text(body: String, id: Int)
	Quit

fn make(s: String, n: Int) Msg:
	return Text(s, n)

fn len(m: Msg) Int:
	return match m:
		Text(body, id): body.length() + id
		Quit: 0

fn temp(n: Int) Int:
	return len(make("abc", n))

fn direct(s: String) Int:
	return match make(s, 1):
		Text(body, _): body.length()
		Quit: 0

fn skip(s: String) Int:
	return match make(s, 1):
		Text(_, id): id
		Quit: 0

fn opt(s: String?) Int:
	return match s:
		v: v.length()
		none: 0

fn fresh(n: Int) String?:
	if n > 0: return "yes"
	return none

fn opt_temp(n: Int) Int:
	return match fresh(n):
		v: v.length()
		none: 0

fn word(s: String) Int:
	return match s:
		"a": 1
		"bb": 2
		"a long literal here": 3
		_: 0

fn word_temp(n: Int) Int:
	return match make("a", n):
		Text(_, _): 1
		Quit: 0

fn main() Int:
	return (
		temp(1)
		+ direct("x")
		+ skip("y")
		+ opt("z")
		+ opt_temp(1)
		+ word("bb")
		+ word_temp(2)
	)
