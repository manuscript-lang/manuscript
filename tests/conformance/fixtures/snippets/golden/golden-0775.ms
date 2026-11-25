// conform: tags=diagnostics
// conform: phase=check
fn f() Void {
	value := {1: 2}
}
// expect-error: MS3000 4:5 local binding value is never read; remove it, use it, or name it with a leading '_' to ignore it
