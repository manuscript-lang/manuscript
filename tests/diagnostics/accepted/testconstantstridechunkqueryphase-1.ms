// conform: tags=control-flow,diagnostics,formatter,interfaces,lists,modules,records,stdlib-cleanup,tier-stdlib
// conform: phase=check,parse
// conform: origin=tests/e2e/counter_chunk_test.go:18 TestConstantStrideChunkQueryPhase
import Closeable from "@std/core.ms"

type Resource {
	visits List[Int]
}

fn move Resource.close() Void! {
	self.visits.append(1)
}
// expect-exit: 0
