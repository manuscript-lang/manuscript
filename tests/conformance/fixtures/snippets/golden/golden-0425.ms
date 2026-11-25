// conform: tags=diagnostics
// conform: phase=check
fn stringify(value Int) String {
	return f"{value}"
}

fn wrong_label(item Int) String {
	return f"{item}"
}

fn callback() Void {
	return
}
