// conform: tags=diagnostics
// conform: phase=check
LIMIT := 10

fn size() Int {
	return LIMIT
}
// expect-exit: 0
