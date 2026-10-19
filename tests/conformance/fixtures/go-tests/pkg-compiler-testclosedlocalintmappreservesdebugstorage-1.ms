# conform: tags=diagnostics,faults,maps,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_int_map_test.go:50 TestClosedLocalIntMapPreservesDebugStorage
fn probe() Int:
    let values = Map[Int, Int]()
    values.add(1, 2)
    return values.get(1).get()
