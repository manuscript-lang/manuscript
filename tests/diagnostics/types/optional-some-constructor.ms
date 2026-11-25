// conform: tags=optional,diagnostics
// conform: phase=check
// An Optional has no `some(...)` constructor: a plain value converts where a `T?` is
// expected.
fn pick(n Int) Int? {
	if n > 2 { return some(n * 2) }
	return null
}

fn main() Void {
	print((pick(3) or 0))
}
// expect-error: MS3000 6:23 there is no some(...); a plain value converts where a T? is expected, so pass it directly, or annotate the binding, e.g. x Int? := 5
