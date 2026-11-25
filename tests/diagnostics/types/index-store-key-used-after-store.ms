// conform: tags=diagnostics,tier-core
// conform: phase=check
fn run(w String) Map[String, Int] {
	var m = Map[String, Int]()
	k := w.clone()
	m[k] = k.length()
	print(k)
	return m
}
// expect-error: MS3000 6:7 `k` is moved here but used again at 7:11; a value has one owner, so move it only at its last use, or pass `k.clone()` if the original is still needed
