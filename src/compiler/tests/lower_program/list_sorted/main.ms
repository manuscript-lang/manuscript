fn by_size(a: Int, b: Int) Int:
	return a - b

fn longest_first(a: String, b: String) Int:
	return b.length() - a.length()

fn main() Void:
	xs := [3, 1, 2]
	ys := xs.sorted(fn a, b: b - a)
	zs := [5, 4].sorted(by_size)
	names := ["fig", "pear", "kiwi"].sorted(longest_first)
	print(ys[0] + zs[0])
	print(names.length())
	print(xs.sorted(fn a, b: a.compare(b)).length())

	fs := [2.5, 0.5].sorted(fn a, b: a.compare(b))
	print(fs[0])
