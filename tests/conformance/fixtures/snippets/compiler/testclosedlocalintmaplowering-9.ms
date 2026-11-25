// conform: tags=diagnostics,maps,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/local_int_map_test.go:34 TestClosedLocalIntMapLowering
fn consume(values Map[Int, Int]) Void => void

fn probe() Int { ... }
// expect-error: MS3000 6:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
