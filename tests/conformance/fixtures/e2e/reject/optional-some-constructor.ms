// conform: tags=optional,diagnostics
// conform: phase=check
// An Optional has no `some(...)` constructor: a plain value converts where a `T?` is expected.
fn pick(n: Int) Int?:
	if n > 2: return some(n * 2)
	return null

fn main() Void:
	print((pick(3) or 0))
