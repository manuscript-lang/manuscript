// conform: tags=testing,tier-core
// conform: phase=check
// `slice(..)?` and `.get_or(..)` hand back the payload of a lent slice, so a `var` that owns it needs `.clone()`.
export fn main() Int {
	xs := [1, 2, 3, 4]
	var a = xs.slice(1, 3).get_or([])
	a.append(9)
	return a.length()
}
// expect-error: MS3000 6:28 `slice` borrows `xs`, which this position would keep; store `.clone()` of it, or use it in place
