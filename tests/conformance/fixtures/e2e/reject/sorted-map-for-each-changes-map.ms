// conform: tags=maps,stdlib-collections,diagnostics,tier-stdlib
// conform: phase=check
// `for_each` reads the entries in place, so a callback that changes the map is rejected.
import SortedMap from "@std/collections/sorted.ms"

fn main() Void {
	var m = SortedMap[Int, Int]()
	m.add(1, 1)
	m.for_each((k, v) => m.add(k + 100, v))
}
// expect-error: MS3000 9:7 the closure at 9:16 of `for_each` is moved or changed in place but overlaps the receiver `m`; a moved or changed value cannot also be read or changed through another operand, so pass distinct variables or clone one first
