// conform: tags=diagnostics
// conform: phase=check
fn f(x Int?) Int {
	while true {
		while (
			match x {
				n => true
				null => break
			}
		) {
			break
		}
	}
}
