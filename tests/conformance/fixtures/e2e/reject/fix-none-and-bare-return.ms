// conform: tags=diagnostics,tier-core
// conform: phase=check
fn find() Int?:
	return none

fn run() Unit!:
	if find() != none:
		return
	return
