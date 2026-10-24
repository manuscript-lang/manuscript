# conform: tags=control-flow,formatter,interfaces,lists,modules,parser,records,stdlib-cleanup,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/counter_chunk_test.go:18 TestConstantStrideChunkQueryPhase
from "@std/core.ms" import Closeable

type Resource:
    visits: List[Int]

impl Closeable for Resource:
    var def close() -> Unit:
        self.visits.append(1)
