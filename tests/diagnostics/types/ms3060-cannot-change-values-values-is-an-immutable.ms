// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn probe() Int {
	values := Map[Int, Int]()
	values.add(1, 2)
	return values.get(1) or panic("called Optional.get() on null")
}
// expect-error: MS3060 7:5 cannot change `values`: `values` is an immutable binding, immutable including its contents; declare it `var values` to change it
// expect-fix: 6:5-6:14 "var values ="
