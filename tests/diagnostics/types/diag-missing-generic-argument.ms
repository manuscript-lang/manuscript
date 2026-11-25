// conform: tags=diagnostics,tier-core
// conform: phase=check
fn map_all[T, U](xs List[T], f fn(T) U) List[U] {
	return []
}

export fn main() Int {
	print(map_all([1, 2]))
	return 0
}
// expect-error: MS3003 8:11 missing argument f: fn(Int) _ in call to map_all; add 'f: <fn(Int) _>'
