fn same(a: String, b: String) Bool:
	return a.equal_fold(b)

fn main() Void:
	print(same("Ab", "aB"))
