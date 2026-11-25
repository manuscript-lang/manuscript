// conform: tags=diagnostics,maps,modules,tier-core
// conform: phase=check
// conform: origin=tests/e2e/map_add_scope_test.go:15 TestMapAddRawKeyDoesNotSeeLocalHashable
import Key from "./domain.ms"

fn invalid() Void {
	m := Map[Key, Int]()
	m.add(Key(-1.0), 1)
}
// expect-error: MS2002 4:1 cannot find module ./domain.ms (looked for domain.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
