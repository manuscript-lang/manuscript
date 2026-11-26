// conform: tags=testing,tier-core
// conform: phase=check
import panic from "@std/core.ms"

test "the map cannot change while a var borrows its entry" {
	var m Map[String, List[Int]] = {"a": [1]}
	var entry = m.get("a") or panic("called Optional.get() on null")
	m.add("b", [2])
	entry.append(2)
}
// expect-error: MS3000 8:5 cannot change `m` while `entry` borrows it (mutable borrow, at 7:9); finish using `entry` before this, or give `entry` its own value by ending its initializer with `.clone()`
