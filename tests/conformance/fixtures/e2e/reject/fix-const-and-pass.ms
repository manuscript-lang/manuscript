// conform: tags=diagnostics,tier-core
// conform: phase=check
const LIMIT = 3
const NAME: String = "a"

fn run() Int {
	if true {
		pass
	}
	return LIMIT
}
