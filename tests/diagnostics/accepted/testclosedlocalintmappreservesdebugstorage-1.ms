// conform: tags=diagnostics,faults,formatter,maps,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/local_int_map_test.go:50 TestClosedLocalIntMapPreservesDebugStorage
import panic from "@std/core.ms"

fn probe() Int {
	var values = Map[Int, Int]()
	values.add(1, 2)
	return values.get(1) or panic("called Optional.get() on null")
}
// expect-exit: 0
