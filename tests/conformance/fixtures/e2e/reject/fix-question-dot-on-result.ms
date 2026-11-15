// conform: tags=diagnostics,tier-core
// conform: phase=check
fn parse(s: String) Result[Int, Error]:
	return s.parse_int().ok_or(Error("bad"))

fn run() Result[Int, Error]:
	x := parse("3")?.abs()
	return ok(x)
