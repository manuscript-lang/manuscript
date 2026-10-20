# conform: tags=control-flow,diagnostics,interfaces,lists,modules,records,stdlib-cleanup,stdlib-string,strings,tier-stdlib
# conform: phase=check
# conform: origin=tests/e2e/builder_range_test.go:16 TestBuilderAndRangeQueryStates
import StringBuilder from "@std/string.ms"
import Closeable from "@std/cleanup.ms"
type Resource:
    visits: List[Int]
impl Closeable for Resource:
    fn close() Unit:
        self.visits.append(1)
