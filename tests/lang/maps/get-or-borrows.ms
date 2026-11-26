// conform: tags=maps,tier-core
// conform: phase=run
fn main() Void {
	// `get_or` answers a view of the stored value or of the fallback, and copies neither.
	var names = Map[String, String]()
	names.add("a", "alpha" + " one")

	fallback := "none" + " found"
	present := names.get_or("a", fallback)
	absent := names.get_or("b", fallback)

	// Fresh allocations would overwrite a view of memory that was released too early.
	var noise = List[String]()
	for index in 0..64 {
		noise.append(f"noise {index} {index * 7}")
	}
	print(present)
	print(absent)
	print(absent.length())
	print(noise.length())

	// A value that is itself an Optional is read as stored.
	var maybe = Map[String, String?]()
	maybe.add("a", "five")

	standby String? := "one"
	print(maybe.get_or("a", standby) or "none")
	print(maybe.get_or("b", standby) or "none")
}
// expect-exit: 0
// expect-stdout: alpha one
// expect-stdout: none found
// expect-stdout: 10
// expect-stdout: 64
// expect-stdout: five
// expect-stdout: one
