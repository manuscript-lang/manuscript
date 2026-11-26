// conform: tags=ownership
// conform: phase=run
fn r(hold s String) &String {
	return s
}

fn main() Void {
	base := "base"
	inner := "inner"
	var x = r(base)
	x = r(inner)
	print(x)
	print(base)
	print(inner)
}
// expect-exit: 0
// expect-stdout: inner
// expect-stdout: base
// expect-stdout: inner
