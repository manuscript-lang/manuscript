// conform: tags=aliasing,faults,formatter,generics,maps,parser,strings,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/local_int_map_test.go:79 TestClosedLocalIntMapIsolatesGenericInstances
import panic from "@std/core.ms"

fn lookup[T: Hashable](key: T, value: T) T:
	var values = Map[T, T]()
	values.add(key, value)
	return values.get(key) or panic("called Optional.get() on null")

fn probe() Int:
	number := lookup[Int](1, 2)
	text := lookup[String]("one", "two")
	return number
