// conform: tags=diagnostics
// conform: phase=check
fn answer() Int {
	var total = 0
	total += 2
	return 0
}
// expect-error: MS3000 4:9 local binding total is never read: it is only read to compute its own next value, so nothing observes it; remove it, use it elsewhere, or name it with a leading '_' to ignore it
