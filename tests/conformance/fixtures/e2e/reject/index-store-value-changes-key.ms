// conform: tags=diagnostics,tier-core
// conform: phase=check
fn bump(var s String) Int {
	s = "x"
	return 1
}

fn run(w String) Map[String, Int] {
	var m = Map[String, Int]()
	var k = w.clone()
	m[k] = bump(k)
	return m
}
// expect-error: MS3000 11:5 argument `bump(..)` of `[]=` is moved or changed in place but overlaps argument `k`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
