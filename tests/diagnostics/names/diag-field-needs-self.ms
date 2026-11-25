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
// expect-error: MS2001 8:20 unknown binding name; name is a field of this method's receiver, so write self.name
// expect-fix: 8:20-8:24 "self.name"
