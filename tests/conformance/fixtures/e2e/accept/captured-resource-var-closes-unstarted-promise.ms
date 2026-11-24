// conform: tags=cleanup,resources,promises,closures
// conform: phase=run
// A resource variable a promise's closure changes stays with its maker, which closes it though the work was cancelled before it started.
import promise from "@std/concurrency/promise.ms"

type Door:
	id Int
	opened Bool

fn move Door.close() Void!:
	print("close door")
	return ok()

fn var Door.open() Int:
	self.opened = true
	return self.id

fn main() Void!:
	var door = Door(id: 3, opened: false)
	work := promise(fn: ok(door.open()))
	work.cancel()
	void work.wait()
