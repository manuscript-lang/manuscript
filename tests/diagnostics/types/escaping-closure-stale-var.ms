// conform: tags=closures,mutation,diagnostics,tier-core
// conform: phase=check
fn make() fn(Int) Int {
	var offset = 1
	factory := fn() fn(Int) Int {
		return inner => {
			return inner + offset
		}
	}
	nested := factory()
	offset = 100
	return nested
}
// expect-error: MS3000 6:16 this closure outlives the statement but captures the `var` `offset`, which is used again at 5:16; the closure would keep a stale value, so bind an immutable snapshot with `snapshot := offset` before the closure and capture `snapshot`
