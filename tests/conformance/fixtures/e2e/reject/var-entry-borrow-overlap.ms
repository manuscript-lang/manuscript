// conform: tags=testing,tier-core
// conform: phase=check
import panic from "@std/core.ms"

test "the map cannot change while a var borrows its entry" {
	var m Map[String, List[Int]] = {"a": [1]}
	var entry = m.get("a") or panic("called Optional.get() on null")
	m.add("b", [2])
	entry.append(2)
}
