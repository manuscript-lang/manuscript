// conform: tags=diagnostics,formatter,modules,stdlib-errors,strings,tier-stdlib,try-result
// conform: phase=check,parse
// conform: origin=documentation/core-language/errors/propagation.md:24

fn prepare() Result[Void, Error] => ok()

fn ready_label() Result[String, Error] {
	prepare()?
	return ok("ready")
}
// expect-exit: 0
