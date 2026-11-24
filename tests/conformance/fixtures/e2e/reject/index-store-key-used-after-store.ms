// conform: tags=diagnostics,tier-core
// conform: phase=check
fn run(w String) Map[String, Int]:
	var m = Map[String, Int]()
	k := w.clone()
	m[k] = k.length()
	print(k)
	return m
