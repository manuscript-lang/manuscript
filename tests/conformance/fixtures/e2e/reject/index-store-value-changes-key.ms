// conform: tags=diagnostics,tier-core
// conform: phase=check
fn bump(var s String) Int:
	s = "x"
	return 1

fn run(w String) Map[String, Int]:
	var m = Map[String, Int]()
	var k = w.clone()
	m[k] = bump(k)
	return m
