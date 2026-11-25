// conform: tags=diagnostics,tier-core
// conform: phase=check
type Pair {
	name String
	n Int
}

fn run(w String) Map[String, Int] {
	var m = Map[String, Int]()
	k := w.clone()
	m[k] = Pair(k, 1).n
	return m
}
