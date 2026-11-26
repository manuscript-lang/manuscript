// conform: tags=diagnostics
// conform: phase=check
fn fragment() String => return "x"

fn probe(flag Bool) String {
	b := ""
}
// expect-error: MS3000 5:1 reachable fallthrough in function returning String; end every path with 'return <String>' (or make the last branch return)
