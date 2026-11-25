// conform: tags=diagnostics,tier-core
// conform: phase=check
fn add(out var List[Int], n: Int) Void {
	out.append(n)
}
// expect-error: MS1000 3:12-3:15 'var' goes before the parameter name, not its type; write var out Type
