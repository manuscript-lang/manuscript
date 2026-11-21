fn same[T: Equal](a: T, b: T) Bool:
	return a == b

fn differs[T: Hashable](a: T?, b: T?) Bool:
	return a != b
