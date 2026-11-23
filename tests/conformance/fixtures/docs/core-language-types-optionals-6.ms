// conform: tags=control-flow,diagnostics,optional,strings,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/optionals.md:77
fn greet(name: String?) String:
	value := name
	if value != null: return "Hello, " + value

	return "Hello!"
