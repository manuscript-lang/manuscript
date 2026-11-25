// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/call_depth_test.go:13 TestRunawayRecursionIsAFault
fn depth(n Int) Int {
	return 1 + depth(n + 1)
}

export fn main() Int {
	return depth(0)
}
