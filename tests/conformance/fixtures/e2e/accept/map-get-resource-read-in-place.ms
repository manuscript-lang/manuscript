// conform: tags=records,maps,tier-core
// conform: phase=run
// `if found := m.get(k)` reads the element in place: the map keeps it, so the element closes once,
// when the map does, not at the end of the `if`.
type Handle:
	id: Int

fn move Handle.close() Void!:
	print(f"closed {self.id}")

fn read(m: Map[String, Handle]) Int:
	found := m.get("a")
	if found != null: return found.id

	return 0

export fn main() Int:
	var m: Map[String, Handle] = {}
	m["a"] = Handle(1)

	first := read(m)
	second := read(m)
	print(f"read {first} {second}")
	return 0
