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
// expect-error: MS3000 3:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
