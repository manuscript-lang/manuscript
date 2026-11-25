// conform: tags=ownership
// conform: phase=check
fn r(hold s String) &String {
	return s
}

fn main() Void {
	base := "base"
	var x = "own"
	x = r(base)
	print(x)
}
