// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// A resource read from a list or map with `get`, `first` or `if value :=` is used in
// place; the collection closes each resource exactly once.
type Handle:
	id: Int

fn move Handle.close() Void!:
	print(f"close {self.id}")

fn id_of(handle: Handle) Int:
	return handle.id

export fn main() Int:
	handles := [Handle(1), Handle(2)]
	var by_key = Map[Int, Handle]()
	by_key.add(7, Handle(70))

	first := handles.first()
	if first != null: print(first.id)
	print(handles.get(1).id)
	print(id_of(handles.get(0)))

	found := by_key.get(7)
	if found != null: print(found.id)
	print(by_key.get(7).get().id)
	print("end")
	return 0
