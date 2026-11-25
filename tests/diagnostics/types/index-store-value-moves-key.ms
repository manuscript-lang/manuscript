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
// expect-error: MS3000 11:17 `k` is moved here but used again at 11:7; a value has one owner, so move it only at its last use, or pass `k.clone()` if the original is still needed
