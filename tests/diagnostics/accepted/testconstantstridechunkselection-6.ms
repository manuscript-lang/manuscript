// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/counter_chunk_test.go:41 TestConstantStrideChunkSelection
fn probe() Int {
	var sum = 0
	var i = 0

	while i < 255 {
		sum += 3
		i += 1
	}

	return sum
}
// expect-exit: 0
