# conform: tags=diagnostics,maps,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_int_map_test.go:34 TestClosedLocalIntMapLowering
fn consume(values: Map[Int, Int]) Unit: unit

fn probe() Int:
