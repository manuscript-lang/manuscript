// conform: tags=control-flow,diagnostics,formatter,modules,stdlib-errors,tier-stdlib,try-result
// conform: phase=check,parse
// conform: origin=documentation/core-language/control-flow/conditionals.md:59

fn port(lookup Result[Int, Error]) Int {
	if value := lookup {
		return value
	}
	return 8080
}
// expect-exit: 0
