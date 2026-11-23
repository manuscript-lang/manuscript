// conform: tags=faults,scope-cleanup
// conform: phase=run
type Resource:
	id: Int
	path: String

fn move Resource.close() Void!:
	print(f"closed {self.id}")

fn plain(var value: Resource) Void:
	_bad := [value.id].get(3)

fn main() Void:
	var value = Resource(61, "p".clone())
	plain(value)
