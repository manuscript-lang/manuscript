// conform: tags=optional,diagnostics
// conform: phase=check
// An Optional has no `some(...)` constructor: a plain value converts where a `T?` is expected.
fn pick(n: Int) Int?:
	if n > 2: return some(n * 2)
	return none

fn main() Void:
	print(pick(3).get_or(0))
