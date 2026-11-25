// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	larger := [1, 2, 3, 4, 5]
	nested := [[1, 2], [3, 4]]
}
// expect-error: MS3000 4:5 local binding larger is never read; remove it, use it, or name it with a leading '_' to ignore it
// expect-error: MS3000 5:5 local binding nested is never read; remove it, use it, or name it with a leading '_' to ignore it
