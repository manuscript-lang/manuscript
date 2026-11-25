// conform: tags=diagnostics
// conform: phase=check
fn work() Void {
	values := {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 8, 9: 9, 0: 0}
}
// expect-error: MS3000 4:5 local binding values is never read; remove it, use it, or name it with a leading '_' to ignore it
