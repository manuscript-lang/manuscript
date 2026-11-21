fn plus_one(xs: List[Int]) List[Int]:
	return xs.map(fn(x: Int) Int: return x + 1)

fn entries(m: Map[String, Int]) Int:
	es := m.entries()
	return es.length()

fn distinct(xs: List[Int]) Int:
	s := xs.to_set()
	return s.length()

fn show(x: Int) Void:
	print(x)

fn each(xs: List[Int]) Void:
	xs.for_each(show)

fn first(xs: List[Int]) Int!String:
	return xs.first().ok_or("none")
