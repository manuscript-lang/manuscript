// conform: tags=mutation,maps,control-flow,diagnostics,tier-core
// conform: phase=check
// A loop over a map's entries may read a value that an in-place change would replace; the keys view covers only
// keys, so only a change of the key set (or of a value the loop reads) is rejected.
fn bump(var n String) Void {
	n += "x"
}

fn structural() Void {
	var m = Map[String, String]()
	m["a"] = "1"
	for key in m.keys() {
		m["b"] = "2"
	}
}

fn entries() Void {
	var m = Map[String, String]()
	m["a"] = "1"
	for entry in m {
		bump(m["a"])
		print(entry.value)
	}
}
