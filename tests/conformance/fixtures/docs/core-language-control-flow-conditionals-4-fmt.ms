// conform: tags=control-flow,formatter,optional,parser,strings,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/control-flow/conditionals.md:51
fn greeting(name: String?) String:
	value := name

	if value != null:
		return "Hello, " + value
	else:
		return "Hello!"
