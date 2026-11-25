// conform: tags=diagnostics
// conform: phase=check
type Empty { ... }

fn empty() Void { ... }

fn kept() Int {
	return 3
}
// expect-exit: 0
