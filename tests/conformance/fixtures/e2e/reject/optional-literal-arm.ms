// conform: tags=match,optional,diagnostics,tier-core
// conform: phase=check
// A literal arm over an Optional names the literal's problem, not an empty case.
fn pick(x Int?) Int {
	match x {
		5 => {
			return 1
		}
		null => {
			return 2
		}
	}
}
