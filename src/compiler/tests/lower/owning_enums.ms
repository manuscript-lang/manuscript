enum Tag:
	Named(label: String, id: Int)
	Anon

fn make(s: String, n: Int) Tag:
	return Named(s, n)

fn ident(t: Tag) Int:
	return match t:
		Named(_, id): id
		Anon: 0

fn run(n: Int) Int:
	return ident(make("abc", n))

fn main() Int:
	return run(7)
