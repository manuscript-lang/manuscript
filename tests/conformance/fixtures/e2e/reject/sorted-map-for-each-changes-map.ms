// conform: tags=maps,stdlib-collections,diagnostics,tier-stdlib
// conform: phase=check
// `for_each` reads the entries in place, so a callback that changes the map is rejected.
import SortedMap from "@std/collections/sorted.ms"

fn main() Void {
	var m = SortedMap[Int, Int]()
	m.add(1, 1)
	m.for_each((k, v) => m.add(k + 100, v))
}
