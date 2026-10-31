# conform: tags=control-flow,formatter,interfaces,lists,modules,parser,records,stdlib-cleanup,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/counter_chunk_test.go:18 TestConstantStrideChunkQueryPhase
import Closeable from "@std/core.ms"

type Resource:
    visits: List[Int]

impl Closeable for Resource:
    var fn close() Unit!:
        self.visits.append(1)
        return ok(unit)
