type P:
	name: String

export fn main() Int:
	p := P(name: "a")
	n := p?.name
	return 0
