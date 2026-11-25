// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
	fn g() Void {
		return
	}
}
// expect-error: MS3000 4:8 local binding g is never read; remove it, use it, or name it with a leading '_' to ignore it
