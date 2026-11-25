// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	values := [
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
		23, 24, 25, 26, 27, 28, 29, 30
	]
}
// expect-error: MS3000 4:5 local binding values is never read; remove it, use it, or name it with a leading '_' to ignore it
