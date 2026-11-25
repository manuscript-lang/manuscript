// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn lookup[T Hashable](hold key T, value T) T {
	values := Map[T, T]()
	values.add(key, value)
	return values.get(key) or panic("called Optional.get() on null")
}

fn probe() Int {
	number := lookup[Int](1, 2)
	text := lookup[String]("one", "two")
	return number
}
// expect-error: MS3060 7:5 cannot change `values`: `values` is an immutable binding, immutable including its contents; declare it `var values` to change it
// expect-fix: 6:5-6:14 "var values ="
// expect-error: MS3000 7:16 `key` is moved here but used again at 8:23; a value has one owner, so move it only at its last use, or pass `key.clone()` if the original is still needed
