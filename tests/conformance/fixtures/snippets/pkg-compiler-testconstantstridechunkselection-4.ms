# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/counter_chunk_test.go:28 TestConstantStrideChunkSelection
fn identity(n: Int) Int: return n
fn probe(flag: Bool) Int:
    
