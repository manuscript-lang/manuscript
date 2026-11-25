// conform: tags=closures,resources,tier-core
// conform: phase=run
// An escaping closure owns the resource it captured and closes it when it is dropped,
// not when the maker returns; a resource that holds only plain memory counts the same
// as one with parts.
type Marker {
	id Int
}

fn move Marker.close() Void! {
	print(f"close {self.id}")
}

fn Marker.status() Int {
	return self.id
}

fn use_it(marker Marker) Void {
	return
}

fn make_from_parameter(move marker Marker) fn() Void {
	return () => use_it(marker)
}

fn make_from_local() fn() Void {
	marker := Marker(id: 2)
	return () => use_it(marker)
}

fn bound_temporary() Int {
	read := Marker(id: 3).status
	first := read()
	return first + read()
}

fn main() Void {
	parameter := make_from_parameter(Marker(id: 1))
	parameter()
	print("after parameter call")

	local := make_from_local()
	local()
	print("after local call")
	print(f"bound {bound_temporary()}")
}
// expect-exit: 0
// expect-stdout: after parameter call
// expect-stdout: after local call
// expect-stdout: close 3
// expect-stdout: bound 6
// expect-stdout: close 2
// expect-stdout: close 1
