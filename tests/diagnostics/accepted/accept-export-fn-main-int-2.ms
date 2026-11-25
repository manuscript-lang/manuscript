// conform: tags=diagnostics
// conform: phase=check
export fn main() Int {
	if not false { return 3 }
	return 0
}
// expect-exit: 0
