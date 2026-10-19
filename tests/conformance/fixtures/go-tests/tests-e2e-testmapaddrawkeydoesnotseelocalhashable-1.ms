# conform: tags=diagnostics,maps,modules,tier-core
# conform: phase=check
# conform: origin=tests/e2e/map_add_scope_test.go:15 TestMapAddRawKeyDoesNotSeeLocalHashable
import Key from "./domain.ms"
fn invalid() Unit:
    let m=Map[Key,Int]()
    m.add(Key(-1.0),1)
