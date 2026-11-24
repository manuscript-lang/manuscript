// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn lookup[T Hashable](key T, value T) T:
	values := Map[T, T]()
	values.add(key, value)
	return values.get(key) or panic("called Optional.get() on null")

fn probe() Int:
	number := lookup[Int](1, 2)
	text := lookup[String]("one", "two")
	return number
