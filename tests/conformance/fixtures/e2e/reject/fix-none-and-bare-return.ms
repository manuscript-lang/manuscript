// conform: tags=diagnostics,tier-core
// conform: phase=check
fn find() Int?:
	return null

fn run() Void!:
	if find() != null:
		return
	return
