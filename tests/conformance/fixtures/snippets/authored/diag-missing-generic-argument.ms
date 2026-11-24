// conform: tags=diagnostics,tier-core
// conform: phase=check
fn map_all[T, U](xs List[T], f fn(T) U) List[U] {
	return []
}

export fn main() Int {
	print(map_all([1, 2]))
	return 0
}
