// conform: tags=records,maps,tier-core
// conform: phase=run
// `s := xs.get(i)` and `b := m.get(k)` borrow the element: the collection keeps it and closes it once, when it closes.
type Handle {
	id Int
}

fn move Handle.close() Void! {
	print(f"closed {self.id}")
}

fn from_list(xs List[Handle]) Int {
	h := xs.get(0)
	return h.id
}

fn from_map(m Map[String, Handle], key String) Int {
	found := m.get(key)
	if found != null { return 1 }

	return 0
}

export fn main() Int {
	var xs List[Handle] = [Handle(1)]
	var m Map[String, Handle] = {}
	m["a"] = Handle(2)
	print(f"list {from_list(xs)}")
	print(f"map {from_map(m, "a")} {from_map(m, "b")}")
	return 0
}
