// conform: tags=testing,tier-core
// conform: phase=check
fn bad(m: Map[String, Int]) Unit:
	x := m["a"]?
