// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// A resource with a `close` and nothing to drop is closed once by its owner: a `&`
// result views it (`get_or`), a discarded statement closes the temporary it read
// (`make().view().use()`), and a method value of `remove`, `set` or
// `add` closes what it takes out.
type Marker {
	id Int
}

fn move Marker.close() Void! {
	print(f"closed-{self.id}")
}

fn mk(id Int) Marker {
	print(f"made-{id}")
	return Marker(id)
}

fn hold Marker.view() &Marker => self

fn Marker.touch() Void {
	print(f"touch-{self.id}")
}

fn get_or_named() Void {
	var items = [mk(1)]
	spare := mk(2)
	found := items.get_or(0, spare)
	print(f"found-{found.id}")
}

fn discarded_view() Void {
	mk(3).view().touch()
}

fn removed_by_value() Void {
	var items = [mk(4)]
	remove := items.remove
	remove(0)
}

fn replaced_by_value() Void {
	var items = [mk(5)]
	set := items.set
	set(0, mk(6))
}

fn tested_in_condition() Void {
	if mk(7).view().id == 7 {
		print("then")
	}
}

export fn main() Int {
	get_or_named()
	discarded_view()
	removed_by_value()
	replaced_by_value()
	tested_in_condition()
	return 0
}
// expect-exit: 0
// expect-stdout: made-1
// expect-stdout: made-2
// expect-stdout: found-1
// expect-stdout: closed-2
// expect-stdout: closed-1
// expect-stdout: made-3
// expect-stdout: touch-3
// expect-stdout: closed-3
// expect-stdout: made-4
// expect-stdout: closed-4
// expect-stdout: made-5
// expect-stdout: made-6
// expect-stdout: closed-5
// expect-stdout: closed-6
// expect-stdout: made-7
// expect-stdout: closed-7
// expect-stdout: then
