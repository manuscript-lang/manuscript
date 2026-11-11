// conform: tags=testing,tier-core
// conform: phase=check
type Plain:
	value: Int

export fn main() Int:
	return [Plain(2), Plain(1)].sorted().length()
