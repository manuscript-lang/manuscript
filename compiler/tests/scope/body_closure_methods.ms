fn plus_one(xs: List[Int]) List[Int]:
	return xs.map(fn(x: Int) Int: return x + 1)

fn entries(m: Map[String, Int]) Int:
	es := m.entries()
	return es.length()

fn distinct(xs: List[Int]) Int:
	s := xs.to_set()
	return s.length()
