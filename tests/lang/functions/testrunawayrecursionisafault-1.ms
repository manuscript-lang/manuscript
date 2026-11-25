// conform: tags=formatter,functions,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/call_depth_test.go:13 TestRunawayRecursionIsAFault
fn depth(n Int) Int {
	return 1 + depth(n + 1)
}

export fn main() Int {
	return depth(0)
}
// expect-exit: 139
// expect-stderr: stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead
// expect-stderr:   at testrunawayrecursionisafault-1.ms:5 in depth
// expect-stderr:   ... previous frame repeated <COUNT> more times
