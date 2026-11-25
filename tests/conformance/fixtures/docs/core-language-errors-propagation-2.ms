// conform: tags=diagnostics,modules,stdlib-errors,strings,tier-stdlib,try-result
// conform: phase=check
// conform: origin=documentation/core-language/errors/propagation.md:24

fn prepare() Result[Void, Error] => ok()

fn ready_label() Result[String, Error] {
	prepare()?
	return ok("ready")
}
// expect-exit: 0
