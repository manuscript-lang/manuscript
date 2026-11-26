// conform: tags=diagnostics
// conform: phase=check
fn answer() Void {
	offset := 7
	values := [1].map(outer => [2].map(inner => outer + inner + offset))
}
// expect-error: MS3000 5:5 local binding values is never read; remove it, use it, or name it with a leading '_' to ignore it
