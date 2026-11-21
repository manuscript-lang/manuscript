fn names(xs: List[String]) List[String]:
	return xs.filter(fn s: s.length() > 1)

fn upper(xs: List[String]) List[String]:
	return xs.map(fn s: s.upper())

fn main() Void:
	l1 := [1, 2, 3]
	l2 := l1.map(fn x: x * 2)
	l3 := l2.filter(fn x: x > 2)
	l4 := l3.drop(1)
	l5 := l1.map(fn x: x + 1).filter(fn x: x % 2 == 0)
	print(l4.length() + l5.length())
	print(l4)
	print(l5)
	print(names(["a", "bb", "ccc"]))
	print(upper(["a", "bb"]))
