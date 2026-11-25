// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/core.ms"

fn probe() Int {
	values := Map[Int, Int]()
	values.add(1, 2)
	return values.get(1) or panic("called Optional.get() on null")
}
