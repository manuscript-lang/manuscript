// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
	g := fn(x Int) Result[Int, String] => ok(x)
	return
}
// expect-error: MS3000 4:5 local binding g is never read; remove it, use it, or name it with a leading '_' to ignore it
