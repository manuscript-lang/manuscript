// conform: tags=diagnostics
// conform: phase=check
fn answer() Void {
	values := [1, 2].map(value => value + 1)
}
// expect-error: MS3000 4:5 local binding values is never read; remove it, use it, or name it with a leading '_' to ignore it
