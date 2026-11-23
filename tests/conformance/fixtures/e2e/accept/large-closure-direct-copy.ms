// conform: tags=closures,lists,maps
// conform: phase=run
// A closure too big to inline is called through a plain copy of its code; the copy's
// signature takes the captures and arguments the entry block names, so the module
// verifies.
fn apply(xs: List[Int], f: fn(List[Int]) Int) Int:
	return f(xs)

fn main() Void:
	r := apply(
		[1, 2, 1],
		fn xs:
			var m = Map[Int, Int]()
			for x in xs:
				m[x] = m.get(x).get_or(0) + 1
			return m.length()
	)

	print(r)
