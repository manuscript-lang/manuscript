// conform: tags=diagnostics,parser,tier-core
// conform: phase=check
// conform: origin=agent-bug-bash
fn drain(o Int?) Void:
	while v := o:
		print(v)
