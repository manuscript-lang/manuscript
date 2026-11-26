// conform: tags=aliasing,diagnostics,faults,formatter,generics,maps,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/local_int_map_test.go:79 TestClosedLocalIntMapIsolatesGenericInstances
import panic from "@std/core.ms"

fn lookup[T Hashable](hold key T, value T) T {
	var values = Map[T, T]()
	values.add(key, value)
	return values.get(key) or panic("called Optional.get() on null")
}

fn probe() Int {
	number := lookup[Int](1, 2)
	text := lookup[String]("one", "two")
	return number
}
// expect-error: MS3000 8:16 `key` is moved here but used again at 9:23; a value has one owner, so move it only at its last use, or pass `key.clone()` if the original is still needed
