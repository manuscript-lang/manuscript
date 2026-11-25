// conform: tags=diagnostics
// conform: phase=check
fn consume(values Map[Int, Int]) Void => void

fn probe() Int { ... }
// expect-error: MS3000 5:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
