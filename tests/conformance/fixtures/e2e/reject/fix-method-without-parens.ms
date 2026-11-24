// conform: tags=diagnostics,tier-core
// conform: phase=check
fn count(items List[Int]) Int:
	if items.length > 0:
		return items.length
	return 0
