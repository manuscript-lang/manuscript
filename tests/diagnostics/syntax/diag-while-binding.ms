// conform: tags=diagnostics,parser,tier-core
// conform: phase=check
// conform: origin=agent-bug-bash
fn drain(o Int?) Void {
	while v := o {
		print(v)
	}
}
// expect-error: MS1000 5:13-5:15 while takes a condition, not a binding; to loop while a value is present write 'while true { ... }', test it inside with 'if value != null { ... }' (or 'if name := result { ... }'), and leave with 'else { break }'
