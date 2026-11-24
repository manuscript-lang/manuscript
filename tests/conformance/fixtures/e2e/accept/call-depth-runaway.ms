// conform: tags=control-flow,interfaces,records,tier-core
// conform: phase=run
// Runaway recursion ends the program with the stack overflow report and its own exit status; it is not recoverable.

type Walker:
	step: Int
	limit: Int

fn Walker.walk(n: Int) Int:
	if n == self.limit:
		return 0

	return 1 + self.walk(n: n + self.step)

fn main() Int:
	walker := Walker(step: 1, limit: -1)
	return walker.walk(n: 0)
