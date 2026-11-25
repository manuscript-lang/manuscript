// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/counter_chunk_test.go:28 TestConstantStrideChunkSelection
fn identity(n Int) Int => return n

fn probe(flag Bool) Int { ... }
// expect-error: MS3000 6:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
