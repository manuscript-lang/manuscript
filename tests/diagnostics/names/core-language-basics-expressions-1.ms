// conform: tags=diagnostics,formatter,strings,tier-core,try-result
// conform: phase=check,parse
// conform: origin=documentation/core-language/basics/expressions.md:73
fn load(path String) Config! {
	config := (
		read(path)?
		| parse?
		| normalize
		| validate?
	)
	return ok(config)
}
// expect-error: MS2001 4:22 unknown type Config; declare it with 'type Config:' / 'enum Config:' / 'interface Config:', declare it as a type parameter, or import it
// expect-error: MS2001 9:11 unknown binding validate; declare it with 'validate := ...' before use, define 'fn validate(...) T { ... }', or import it from a module
