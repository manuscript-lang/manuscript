// conform: tags=faults,formatter,maps,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/local_int_map_test.go:50 TestClosedLocalIntMapPreservesDebugStorage
import panic from "@std/core.ms"

fn probe() Int {
	var values = Map[Int, Int]()
	values.add(1, 2)
	return values.get(1) or panic("called Optional.get() on null")
}
