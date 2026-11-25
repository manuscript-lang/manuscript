// conform: tags=diagnostics,strings,tier-core,try-result
// conform: phase=check
// conform: origin=documentation/core-language/types/optionals.md:111
fn port_number(text String) Result[Int, Error] {
	port := ok_or(text.parse_int(), Error("missing"))?
	return ok(port)
}
