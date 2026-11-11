// conform: tags=testing,tier-core
// conform: phase=check
type P:
	name: String

export fn main() Int:
	p := P(name: "a")
	n := p?.name
	return 0
