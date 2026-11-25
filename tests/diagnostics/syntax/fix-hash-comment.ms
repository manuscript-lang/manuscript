// conform: tags=diagnostics,tier-core
// conform: phase=check
# a comment
fn run() Int {
	return 1
}
// expect-error: MS1000 3:1-3:2 unexpected source character '#'; comments start with '//' (or '/* */' for a block)
// expect-fix: 3:1-3:2 "//"
