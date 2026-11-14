// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// A resource read from a list or map with `get`, `first` or `if value :=` is used in place; the
// collection closes each resource exactly once.
type Handle:
	id: Int

fn var Handle.close() Unit!:
	print("close {self.id}")

fn id_of(handle: Handle) Int:
	return handle.id

export fn main() Int:
	handles := [Handle(1), Handle(2)]
	var by_key = Map[Int, Handle]()
	by_key.add(7, Handle(70))
	if first := handles.first(): print(first.id)
	print(handles.get(1).id)
	print(id_of(handles.get(0)))
	if found := by_key.get(7): print(found.id)
	print(by_key.get(7).get().id)
	print("end")
	return 0
