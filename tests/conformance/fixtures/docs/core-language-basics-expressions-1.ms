// conform: tags=diagnostics,strings,tier-core,try-result
// conform: phase=check
// conform: origin=documentation/core-language/basics/expressions.md:73
fn load(path: String) Config!:
	config := read(path)?
		| parse?
		| normalize
		| validate?
	return ok(config)
