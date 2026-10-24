# conform: tags=control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/counter_chunk_test.go:41 TestConstantStrideChunkSelection
def probe() -> Int:
    var sum = 0
    var i = 0

    while i < 255:
        sum += 3
        i += 1

    return sum
