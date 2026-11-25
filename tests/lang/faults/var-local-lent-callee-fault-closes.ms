// conform: tags=faults,scope-cleanup
// conform: phase=run
type Resource {
	id Int
	path String
}

fn move Resource.close() Void! {
	print(f"closed {self.id}")
}

fn plain(var value Resource) Void {
	_bad := [value.id][past_end()]
}

fn main() Void {
	var value = Resource(61, "p".clone())
	plain(value)
}

// An index no check can see is out of range, so the fault happens at run time.
fn past_end() Int => 3
// expect-exit: 134
// expect-stdout: closed 61
// expect-stderr: index 3 out of range for length 1; use get_or(index, default) to avoid the fault
// expect-stderr:   at var-local-lent-callee-fault-closes.ms:13 in plain
// expect-stderr:   at var-local-lent-callee-fault-closes.ms:18 in main
