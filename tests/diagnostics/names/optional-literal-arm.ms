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
// expect-error: MS2001 6:9 a literal pattern cannot match Optional; literals match only Int, String or Bool, so match one of the cases: null, some
