// conform: tags=diagnostics,tier-core
// conform: phase=check
fn width(text String) Int! {
	return ok(text.length())
}

fn total(items List[String]) Int! {
	widths := items.map(item => width(item)?)
	return ok(widths.length())
}
