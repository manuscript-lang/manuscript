// conform: tags=lists,tier-core
// conform: phase=run
// conform: origin=lent-collection-views
// `List.slice` and `Map.keys`/`values` lend their receiver: used in place they copy nothing, and
// a `.clone()` keeps an independent copy even when the receiver changes or dies afterwards.
type Page:
	rows: List[Int]
	names: List[String]

fn total(xs: List[Int]) Int:
	var s = 0
	for x in xs:
		s += x
	return s

fn window(xs: List[Int], a: Int, b: Int) Int:
	return total(xs.slice(a, b).get())

fn keep_window(xs: List[Int], a: Int, b: Int) List[Int]:
	return xs.slice(a, b).get().clone()

fn names_of(m: Map[String, Int]) List[String]:
	return m.keys().clone()

export fn main() Int:
	var xs = [1, 2, 3, 4, 5, 6, 7, 8]
	print(window(xs, 2, 5))
	print(window(xs, -3, 8))
	print(xs.slice(3, 9).is_ok())
	kept := keep_window(xs, 1, 4)
	xs.set(1, 100)
	xs.set(2, 200)
	print(kept)
	print(xs.slice(0, 0).get().length())
	var m = Map[String, Int]()
	m["alpha is a longer string than inline"] = 1
	m["beta is a longer string than inline too"] = 20
	names := names_of(m)
	m["gamma is a longer string than inline as well"] = 300
	print(names.sorted())
	print(total(m.values()))
	var longest = 0
	for k in m.keys():
		longest = longest.max(k.length())
	print(longest)
	longer := m.values().clone()
	m["alpha is a longer string than inline"] = 7
	print(total(longer))
	page := Page(xs.slice(1, 3).get().clone(), m.keys().clone())
	xs.set(1, 0)
	print(page.rows)
	print(page.names.length())
	var windows = List[List[Int]]()
	for i in 0..3:
		windows.append(xs.slice(i, i + 2).get().clone())
	xs.set(0, -1)
	print(windows)
	return 0
