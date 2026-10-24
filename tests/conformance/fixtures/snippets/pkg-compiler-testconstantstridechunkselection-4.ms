# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/counter_chunk_test.go:28 TestConstantStrideChunkSelection
def identity(n: Int) -> Int: return n

def probe(flag: Bool) -> Int: ...
