fn push_one(var values: List[Int]) Unit:
	values.append(1)

export fn main() Int:
	var values: List[Int] = []
	change: fn(var List[Int]) Unit = push_one

	// The function type changes its parameter, so the call must say so.
	change(values)
	return values.length() - 1
