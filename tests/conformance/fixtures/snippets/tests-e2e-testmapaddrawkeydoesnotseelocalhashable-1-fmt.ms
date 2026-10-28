# conform: tags=formatter,maps,modules,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/map_add_scope_test.go:15 TestMapAddRawKeyDoesNotSeeLocalHashable
import Key from "./domain.ms"

fn invalid() Unit:
    let m = Map[Key, Int]()
    m.add(Key(-1.0), 1)
