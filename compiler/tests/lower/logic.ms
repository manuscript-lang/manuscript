fn both(a: Bool, b: Bool) Bool:
	return a and b

fn either(a: Bool, b: Bool) Bool:
	return a or b

fn mixed(a: Int, b: Int, c: Bool) Bool:
	return a < b and (c or a == b) and not (a != 0)

fn same(a: Bool, b: Bool) Bool:
	return a == b

fn near(x: Float, y: Float) Bool:
	return x <= y or x != y

fn main() Int:
	if both(true, false) or either(true, false): return 1
	if mixed(1, 2, true) and same(true, false) and near(1.0, 2.0): return 2

	return 0
