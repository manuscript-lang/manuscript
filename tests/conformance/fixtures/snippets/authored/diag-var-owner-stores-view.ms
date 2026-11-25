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
// expect-error: MS3000 10:9 `r` returns a reference into `base`, which this position would keep; store `.clone()` of it, or use it in place
