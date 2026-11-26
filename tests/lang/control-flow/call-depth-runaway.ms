// conform: tags=control-flow,interfaces,records,tier-core
// conform: phase=run
// Runaway recursion ends the program with the stack overflow report and its own exit
// status; it is not recoverable.

type Walker {
	step Int
	limit Int
}

fn Walker.walk(n Int) Int {
	if n == self.limit {
		return 0
	}
	return 1 + self.walk(n: n + self.step)
}

fn main() Int {
	walker := Walker(step: 1, limit: -1)
	return walker.walk(n: 0)
}
// expect-exit: 139
// expect-stderr: stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead
// expect-stderr:   at call-depth-runaway.ms:13 in Walker.walk
// expect-stderr:   at call-depth-runaway.ms:15 in Walker.walk
// expect-stderr:   ... previous frame repeated <COUNT> more times
