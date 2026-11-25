// conform: tags=testing,tier-core
// conform: phase=check
fn push_one(var values List[Int]) Void {
	values.append(1)
}

export fn main() Int {
	var values List[Int] = []
	// The parameter says `var`; a call never writes it.
	push_one(var values)
	return values.length() - 1
}
// expect-error: MS1000 10:14-10:18 a call does not write `var`: the callee's parameter declares that it changes the argument; write the argument plainly
// expect-fix: 10:14-10:18 ""
