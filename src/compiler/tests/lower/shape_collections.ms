fn numbers(xs: List[Int]) String:
	return f"<{xs}>"

fn maybe(best: Int?) String:
	return f"<{best}>"

fn words(names: List[String]) String:
	return f"<{names}>"

fn main() Int:
	xs := [1, 2, 3]
	a := numbers(xs)
	b := maybe(4)
	c := words(["x", ""])
	return a.length() + b.length() + c.length()
