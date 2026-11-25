// conform: tags=diagnostics,tier-core
// conform: phase=check
type P {
	name String
}

fn P.greet() String {
	return "hi " + name
}

export fn main() Int {
	print(P("a").greet())
	return 0
}
