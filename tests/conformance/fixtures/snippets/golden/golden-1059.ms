// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	values := [
		1,  // Keep the first value explained.
		2,
		3,
		4
	]
}
// expect-error: MS3000 4:5 local binding values is never read; remove it, use it, or name it with a leading '_' to ignore it
